#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_AI_COMMAND_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../../db/ai.sh
source "${LIB_DIR}/db/ai.sh"
# shellcheck source=../window/close.sh
source "${LIB_DIR}/commands/window/close.sh"

ai_capture_window_screenshot() {
    local uuid="$1"
    local window_name="$2"
    local safe_name=""
    safe_name=$(echo "$window_name" | tr -c '[:alnum:]_.-' '_')

    local screenshot_dir="${AI_SCREENSHOT_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/kdoitall/ai-screenshots}"
    mkdir -p "$screenshot_dir"

    local output_path="${screenshot_dir}/${safe_name}.png"
    local cmd_template="${AI_SCREENSHOT_CMD:-kdotool window screenshot \"{uuid}\" \"{path}\"}"
    local cmd="${cmd_template//\{uuid\}/$uuid}"
    cmd="${cmd//\{path\}/$output_path}"

    if eval "$cmd" >/dev/null 2>&1; then
        echo "$output_path"
        return 0
    fi

    echo ""
    return 1
}

ai_collect_windows_json() {
    local windows=()

    while IFS='|' read -r window_name workspace class title uuid; do
        [[ -z "$window_name" ]] && continue
        local screenshot_path=""
        screenshot_path=$(ai_capture_window_screenshot "$uuid" "$window_name" || true)
        windows+=("$(jq -cn \
            --arg wn "$window_name" \
            --arg ws "$workspace" \
            --arg c "$class" \
            --arg t "$title" \
            --arg u "$uuid" \
            --arg sp "$screenshot_path" \
            '{window_name:$wn,workspace:$ws,class:$c,title:$t,uuid:$u,screenshot:$sp}')")
    done < <(db_ai_get_windows_snapshot)

    printf '%s\n' "${windows[@]}" | jq -s '.'
}

ai_collect_popup_candidates_json() {
    local windows=()

    while IFS='|' read -r window_name workspace class title uuid; do
        [[ -z "$window_name" ]] && continue
        local screenshot_path=""
        screenshot_path=$(ai_capture_window_screenshot "$uuid" "$window_name" || true)
        windows+=("$(jq -cn \
            --arg wn "$window_name" \
            --arg ws "$workspace" \
            --arg c "$class" \
            --arg t "$title" \
            --arg u "$uuid" \
            --arg sp "$screenshot_path" \
            '{window_name:$wn,workspace:$ws,class:$c,title:$t,uuid:$u,screenshot:$sp}')")
    done < <(db_ai_get_popup_candidates)

    printf '%s\n' "${windows[@]}" | jq -s '.'
}

ai_analyze() {
    local task_name="${1:-general desktop task}"
    local run_id=""
    run_id="$(date +%Y%m%d%H%M%S)"

    ensure_ai_tables
    auto_detect_windows

    local windows_json=""
    windows_json=$(ai_collect_windows_json)

    if [[ "$windows_json" == "[]" ]]; then
        echo "No windows found to analyze." >&3
        return 1
    fi

    local model_output=""
    model_output=$(python3 "${LIB_DIR}/ai/openai_client.py" rank "$task_name" "$windows_json")

    local api_error=""
    api_error=$(echo "$model_output" | jq -r '.error // empty')
    if [[ -n "$api_error" ]]; then
        echo "AI analysis failed: $api_error" >&3
        return 1
    fi

    local task_summary=""
    task_summary=$(echo "$model_output" | jq -r '.task_summary // "(none)"')
    local sqlite_state_summary=""
    sqlite_state_summary=$(echo "$model_output" | jq -r '.sqlite_state_summary // "(none)"')

    echo "Task Summary: $task_summary" >&3
    echo "SQLite Summary: $sqlite_state_summary" >&3
    echo "" >&3
    echo "Window importance ranking:" >&3

    while IFS='|' read -r window_name importance action reason; do
        db_query "SELECT workspace_name, class, COALESCE(window_title,''), COALESCE(uuid,'') FROM app_windows WHERE window_name = :window_name;" \
            ":window_name" "$window_name"
        local workspace=""
        local class=""
        local title=""
        local uuid=""
        if [[ ${#DB_RESULT[@]} -gt 0 ]]; then
            IFS='|' read -r workspace class title uuid <<< "${DB_RESULT[0]}"
        fi

        local screenshot_path=""
        screenshot_path=$(ai_capture_window_screenshot "$uuid" "$window_name" || true)
        db_ai_record_window_score "$run_id" "$task_name" "$window_name" "$workspace" "$class" "$title" "$importance" "$action" "$reason" "$screenshot_path"
        printf '  %3s  %-30s action=%-8s reason=%s\n' "$importance" "$window_name" "$action" "$reason" >&3
    done < <(echo "$model_output" | jq -r '.window_scores[]? | [.window_name, (.importance|tostring), .suggested_action, .reason] | @tsv')

    db_ai_record_run_summary "$run_id" "$task_name" "${OPENAI_MODEL:-gpt-5}" "$task_summary" "$sqlite_state_summary" ""

    echo "" >&3
    echo "Recommended automation cycle:" >&3
    echo "$model_output" | jq -r '.automation_cycle[]? | "  - " + .' >&3

    db_ai_start_cycle "$task_name" "AI analysis run $run_id"
    local step
    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        db_ai_step_cycle "$task_name" "planned" "$step"
    done < <(echo "$model_output" | jq -r '.automation_cycle[]?')
}

ai_popup_link() {
    local task_name="${1:-general desktop task}"
    local run_id=""
    run_id="$(date +%Y%m%d%H%M%S)-popup"

    ensure_ai_tables
    auto_detect_windows

    local windows_json=""
    windows_json=$(ai_collect_windows_json)
    local candidates_json=""
    candidates_json=$(ai_collect_popup_candidates_json)

    if [[ "$windows_json" == "[]" ]]; then
        echo "No windows found." >&3
        return 1
    fi

    if [[ "$candidates_json" == "[]" ]]; then
        echo "No popup-like candidates found in current sqlite state." >&3
        return 0
    fi

    local model_output=""
    model_output=$(python3 "${LIB_DIR}/ai/openai_client.py" popup-link "$task_name" "$windows_json" "$candidates_json")

    local api_error=""
    api_error=$(echo "$model_output" | jq -r '.error // empty')
    if [[ -n "$api_error" ]]; then
        echo "AI popup linking failed: $api_error" >&3
        return 1
    fi

    local popup_link_summary=""
    popup_link_summary=$(echo "$model_output" | jq -r '.popup_link_summary // "(none)"')
    local sqlite_change_summary=""
    sqlite_change_summary=$(echo "$model_output" | jq -r '.sqlite_change_summary // "(none)"')

    echo "Popup Link Summary: $popup_link_summary" >&3
    echo "SQLite Change Summary: $sqlite_change_summary" >&3
    echo "" >&3
    echo "Inferred popup relationships:" >&3

    while IFS='|' read -r parent child link_type confidence rationale; do
        [[ -z "$parent" || -z "$child" ]] && continue
        db_ai_record_window_link "$run_id" "$task_name" "$parent" "$child" "$link_type" "$confidence" "$rationale"
        printf '  %-30s -> %-30s type=%-12s conf=%-3s reason=%s\n' "$parent" "$child" "$link_type" "$confidence" "$rationale" >&3
    done < <(echo "$model_output" | jq -r '.popup_links[]? | [.parent_window_name, .child_window_name, .link_type, (.confidence|tostring), .rationale] | @tsv')

    db_ai_record_run_summary "$run_id" "$task_name" "${OPENAI_MODEL:-gpt-5}" "" "$sqlite_change_summary" "$popup_link_summary"
}

ai_sqlite_summary() {
    local task_name="${1:-}"
    local summary_line=""

    summary_line=$(db_ai_get_latest_run_summary "$task_name" | head -n1)
    if [[ -z "$summary_line" ]]; then
        echo "No AI run summaries found." >&3
        return 0
    fi

    local run_id="" task="" model="" task_summary="" sqlite_summary="" popup_summary="" created_at=""
    IFS='|' read -r run_id task model task_summary sqlite_summary popup_summary created_at <<< "$summary_line"

    echo "Latest AI SQLite Summary" >&3
    echo "  run_id:      $run_id" >&3
    echo "  task:        $task" >&3
    echo "  model:       $model" >&3
    echo "  created_at:  $created_at" >&3
    echo "  task_summary: $task_summary" >&3
    echo "  sqlite_state: $sqlite_summary" >&3
    echo "  popup_links:  $popup_summary" >&3

    local link_count=0
    while IFS='|' read -r _parent _child _type _confidence _rationale; do
        ((link_count++))
    done < <(db_ai_get_latest_window_links "$task")

    echo "  linked_popups: $link_count" >&3
}

ai_prune() {
    local threshold="${1:-40}"
    local apply_mode="${2:-}"

    ensure_ai_tables

    local close_count=0
    while IFS='|' read -r window_name workspace class title importance action reason; do
        [[ -z "$window_name" ]] && continue
        if (( importance < threshold )); then
            echo "Candidate close: $window_name (importance=$importance, reason=$reason)" >&3
            if [[ "$apply_mode" == "--apply" ]]; then
                window_close "$window_name" || true
                ((close_count++))
            fi
        fi
    done < <(db_ai_get_latest_window_scores)

    if [[ "$apply_mode" == "--apply" ]]; then
        echo "Closed $close_count low-importance windows." >&3
    else
        echo "Dry-run only. Re-run with --apply to close windows." >&3
    fi
}

ai_link() {
    local window_name="$1"
    local task_name="$2"
    local reason="${3:-linked by operator}"

    if [[ -z "$window_name" || -z "$task_name" ]]; then
        echo "Usage: kdoitall ai link <window-name> <task-name> [reason]" >&3
        return 1
    fi

    ensure_ai_tables
    db_ai_link_task_window "$task_name" "$window_name" "$reason"
    echo "Linked window '$window_name' to task '$task_name'." >&3
}

ai_cycle() {
    local action="$1"
    local cycle_name="$2"
    local notes="${3:-}"

    ensure_ai_tables

    case "$action" in
        start)
            db_ai_start_cycle "$cycle_name" "${notes:-cycle started manually}"
            echo "Started cycle '$cycle_name'." >&3
            ;;
        step)
            db_ai_step_cycle "$cycle_name" "active" "${notes:-manual step}"
            echo "Added step to cycle '$cycle_name'." >&3
            ;;
        done)
            db_ai_step_cycle "$cycle_name" "done" "${notes:-cycle completed}"
            echo "Marked cycle '$cycle_name' done." >&3
            ;;
        status)
            while IFS='|' read -r name step status row_notes created_at; do
                printf '%-20s step=%-3s status=%-8s at=%s notes=%s\n' "$name" "$step" "$status" "$created_at" "$row_notes" >&3
            done < <(db_ai_cycle_status "$cycle_name")
            ;;
        *)
            echo "Usage: kdoitall ai cycle <start|step|done|status> <cycle-name> [notes]" >&3
            return 1
            ;;
    esac
}

ai_ideas() {
    local context="${1:-KDE desktop automation improvements}"
    local model_output=""

    model_output=$(python3 "${LIB_DIR}/ai/openai_client.py" ideas "$context")
    local api_error=""
    api_error=$(echo "$model_output" | jq -r '.error // empty')

    if [[ -n "$api_error" ]]; then
        echo "AI ideas generation failed: $api_error" >&3
        return 1
    fi

    echo "15 cool ideas:" >&3
    echo "$model_output" | jq -r '.ideas[]? | "- " + .' >&3
}

ai_command() {
    local subcommand="${1:-}"
    shift || true

    case "$subcommand" in
        analyze)
            ai_analyze "$@"
            ;;
        popup-link)
            ai_popup_link "$@"
            ;;
        sqlite-summary)
            ai_sqlite_summary "$@"
            ;;
        prune)
            ai_prune "$@"
            ;;
        link)
            ai_link "$@"
            ;;
        cycle)
            ai_cycle "$@"
            ;;
        ideas)
            ai_ideas "$@"
            ;;
        *)
            cat << 'EOF_HELP' >&3
Usage: kdoitall ai <subcommand> [args]

Subcommands:
  analyze [task-name]                 Rank windows by importance for a task
  popup-link [task-name]              Link popup/dialog windows to parent windows
  sqlite-summary [task-name]          Summarize latest AI sqlite state and links
  prune [threshold] [--apply]         Close low-importance windows from latest rank
  link <window> <task> [reason]       Link a window to a task
  cycle <action> <name> [notes]       Manage automation/change cycles
  ideas [context]                     Generate 15 cool feature ideas
EOF_HELP
            return 1
            ;;
    esac
}
