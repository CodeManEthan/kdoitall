#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Interactive tool for gathering app metadata and populating database/app-registry.sql
#
# Usage:
#   ./scripts/build-app-registry.sh <app_id>        # Gather metadata for an app
#   ./scripts/build-app-registry.sh --list           # Show all registry entries

set -euo pipefail

# ============================================================================
# Environment Setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KDOITALL_ROOT="$(dirname "$SCRIPT_DIR")"
export LIB_DIR="${KDOITALL_ROOT}/lib"

readonly REGISTRY_SQL="${KDOITALL_ROOT}/database/app-registry.sql"

# fd 3 for user-facing display output
exec 3>&1

# --- Layer 1 — Foundation ---
# shellcheck source=../lib/core/error-codes.sh
source "${LIB_DIR}/core/error-codes.sh"
# shellcheck source=../lib/utils/debug.sh
source "${LIB_DIR}/utils/debug.sh"

# --- Layer 2 — Core Utilities ---
# shellcheck source=../config
source "${KDOITALL_ROOT}/config"
# shellcheck source=../lib/core/common.sh
source "${LIB_DIR}/core/common.sh"
# shellcheck source=../lib/utils/checks.sh
source "${LIB_DIR}/utils/checks.sh"
# shellcheck source=../lib/utils/validators.sh
source "${LIB_DIR}/utils/validators.sh"

# --- Layer 3 — Core Services ---
# shellcheck source=../lib/db/helpers.sh
source "${LIB_DIR}/db/helpers.sh"
# shellcheck source=../lib/core/database.sh
source "${LIB_DIR}/core/database.sh"

# --- Runtime Modules ---
# shellcheck source=../lib/utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

# ============================================================================
# Globals
# ============================================================================

LAUNCHED_UUIDS=()
CONFIRM_RESULT=""

# ============================================================================
# Utility Functions
# ============================================================================

derive_app_name() {
    local display_name="$1"
    echo "$display_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g'
}

find_desktop_file() {
    local app_id="$1"
    local dir=""
    for dir in "${DESKTOP_FILE_LOCATIONS[@]}"; do
        if [[ -f "${dir}/${app_id}.desktop" ]]; then
            echo "${dir}/${app_id}.desktop"
            return 0
        fi
    done
    return 1
}

extract_display_name() {
    local desktop_file="$1"
    grep -m1 '^Name=' "$desktop_file" | cut -d'=' -f2-
}

# Returns "active", "commented", or empty string.
check_existing_entry() {
    local app_id="$1"
    if grep -q "^INSERT INTO app_registry VALUES ('${app_id}'," "$REGISTRY_SQL"; then
        echo "active"
    elif grep -q "^--INSERT INTO app_registry VALUES ('${app_id}'," "$REGISTRY_SQL"; then
        echo "commented"
    fi
}

get_existing_line() {
    local app_id="$1"
    grep "INSERT INTO app_registry VALUES ('${app_id}'," "$REGISTRY_SQL" | head -1
}

close_launched_windows() {
    if [[ ${#LAUNCHED_UUIDS[@]} -eq 0 ]]; then
        return 0
    fi
    local uuid=""
    for uuid in "${LAUNCHED_UUIDS[@]}"; do
        close_window "$uuid" 2>/dev/null || true
    done
    LAUNCHED_UUIDS=()
}

# ============================================================================
# Interactive UI Helpers
# ============================================================================

# Generic confirm/retry/edit for a detected value.
# Sets CONFIRM_RESULT to the confirmed value, or "RETRY" if user chose retry.
confirm_field() {
    local field_name="$1"
    local detected_value="$2"
    local allow_retry="${3:-true}"

    CONFIRM_RESULT=""

    while true; do
        echo "" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "  ${field_name}" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3
        echo "  Detected: ${detected_value}" >&3
        echo "" >&3
        echo "  [C] Confirm" >&3
        if [[ "$allow_retry" == "true" ]]; then
            echo "  [R] Retry (re-detect)" >&3
        fi
        echo "  [E] Edit (enter manually)" >&3
        echo "" >&3

        local choice=""
        read -r -p "Choice: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

        case "$choice" in
            c|"")
                CONFIRM_RESULT="$detected_value"
                return 0
                ;;
            r)
                if [[ "$allow_retry" == "true" ]]; then
                    CONFIRM_RESULT="RETRY"
                    return 0
                fi
                print_error "Retry not available for this field."
                ;;
            e)
                local new_value=""
                read -r -p "Enter value: " new_value
                if [[ -n "$new_value" ]]; then
                    CONFIRM_RESULT="$new_value"
                    return 0
                fi
                print_warning "Empty value not allowed."
                ;;
            *)
                print_error "Invalid choice."
                ;;
        esac
    done
}

# Splash window confirm with toggle. Sets CONFIRM_RESULT.
confirm_splash_field() {
    local detected_value="$1"

    CONFIRM_RESULT=""

    local toggle_to="true"
    [[ "$detected_value" == "true" ]] && toggle_to="false"

    while true; do
        echo "" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "  has_splash_window" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3
        echo "  Detected: ${detected_value}" >&3
        echo "" >&3
        echo "  [C] Confirm" >&3
        echo "  [E] Toggle (switch to ${toggle_to})" >&3
        echo "" >&3

        local choice=""
        read -r -p "Choice: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

        case "$choice" in
            c|"")
                CONFIRM_RESULT="$detected_value"
                return 0
                ;;
            e)
                CONFIRM_RESULT="$toggle_to"
                return 0
                ;;
            *)
                print_error "Invalid choice."
                ;;
        esac
    done
}

# Title pattern selection with numbered suggestions. Sets CONFIRM_RESULT.
select_title_pattern() {
    local current_title="$1"

    CONFIRM_RESULT=""

    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "  window_title_pattern" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "  Window title: \"${current_title}\"" >&3
    echo "" >&3

    local -a suggestions=()
    mapfile -t suggestions < <(parse_window_title_segments "$current_title")

    if [[ ${#suggestions[@]} -eq 0 ]]; then
        print_info "No separators found in title."
        echo "" >&3
        echo "  [1] Use full title as pattern" >&3
        echo "  [2] Enter custom pattern" >&3
        echo "  [0] No pattern (skip)" >&3
        echo "" >&3

        local choice=""
        read -r -p "Select: " choice

        case "$choice" in
            1) CONFIRM_RESULT="$current_title" ;;
            2)
                local pattern=""
                read -r -p "Enter pattern: " pattern
                CONFIRM_RESULT="$pattern"
                ;;
            *) CONFIRM_RESULT="" ;;
        esac
        return 0
    fi

    echo "  Suggestions (rightmost first):" >&3
    echo "" >&3

    local i=1
    local suggestion=""
    for suggestion in "${suggestions[@]}"; do
        echo "  [$i] \"$suggestion\"" >&3
        ((i++))
    done

    echo "  [$i] Custom pattern" >&3
    local custom_option=$i
    echo "  [0] No pattern (skip)" >&3
    echo "" >&3

    local choice=""
    read -r -p "Select (0-$i): " choice

    if [[ -z "$choice" || "$choice" == "0" ]]; then
        CONFIRM_RESULT=""
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        print_error "Invalid choice. Skipping."
        CONFIRM_RESULT=""
        return 0
    fi

    if [[ "$choice" -eq "$custom_option" ]]; then
        local pattern=""
        read -r -p "Enter pattern: " pattern
        CONFIRM_RESULT="$pattern"
        return 0
    fi

    local idx=$((choice - 1))
    if [[ "$idx" -ge 0 && "$idx" -lt "${#suggestions[@]}" ]]; then
        CONFIRM_RESULT="${suggestions[$idx]}"
        return 0
    fi

    print_error "Choice out of range. Skipping."
    CONFIRM_RESULT=""
    return 0
}

# ============================================================================
# File Operations
# ============================================================================

# Parse category comments from app-registry.sql.
# Outputs "line_number|category_name" entries on stdout.
parse_registry_categories() {
    local line_number=0
    local line=""
    while IFS= read -r line; do
        ((line_number++)) || true
        # Match "-- Category Name" but not "--INSERT ..."
        if [[ "$line" =~ ^--\ [A-Z] && ! "$line" =~ ^--INSERT ]]; then
            echo "${line_number}|${line#-- }"
        fi
    done < "$REGISTRY_SQL"
}

# Find the last INSERT line (commented or not) within a category section.
# Returns the 1-indexed line number.
find_category_last_insert() {
    local category_start_line="$1"
    local last_insert_line="$category_start_line"
    local line_number=0
    local in_section=false
    local line=""

    while IFS= read -r line; do
        ((line_number++)) || true

        if [[ "$line_number" -eq "$category_start_line" ]]; then
            in_section=true
            continue
        fi

        if [[ "$in_section" == "true" ]]; then
            # Hit next category header — stop
            if [[ "$line" =~ ^--\ [A-Z] && ! "$line" =~ ^--INSERT ]]; then
                break
            fi
            if [[ "$line" == *"INSERT INTO app_registry"* ]]; then
                last_insert_line="$line_number"
            fi
        fi
    done < "$REGISTRY_SQL"

    echo "$last_insert_line"
}

# Write or replace an entry in app-registry.sql.
# Uses mapfile to read/modify/write (avoids sed escaping issues).
write_registry_entry() {
    local app_id="$1"
    local insert_line="$2"
    local mode="$3"           # "replace", "insert", or "append"
    local after_line="${4:-}"  # 1-indexed line number (for "insert" mode)

    local -a file_lines=()
    mapfile -t file_lines < "$REGISTRY_SQL"

    if [[ "$mode" == "replace" ]]; then
        local i=""
        for i in "${!file_lines[@]}"; do
            if [[ "${file_lines[$i]}" == *"INSERT INTO app_registry VALUES ('${app_id}',"* ]]; then
                file_lines[$i]="$insert_line"
                break
            fi
        done
    elif [[ "$mode" == "insert" ]]; then
        local idx=$((after_line - 1))
        local -a new_lines=()
        new_lines=("${file_lines[@]:0:$((idx + 1))}" "$insert_line" "${file_lines[@]:$((idx + 1))}")
        file_lines=("${new_lines[@]}")
    elif [[ "$mode" == "append" ]]; then
        file_lines+=("$insert_line")
    fi

    printf '%s\n' "${file_lines[@]}" > "$REGISTRY_SQL"
}

# ============================================================================
# --list Handler
# ============================================================================

list_registry() {
    echo "" >&3
    echo "App Registry Entries:" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3

    local active_count=0
    local commented_count=0
    local total_count=0
    local line=""

    while IFS= read -r line; do
        # Category headers
        if [[ "$line" =~ ^--\ [A-Z] && ! "$line" =~ ^--INSERT ]]; then
            echo "" >&3
            echo "$line" >&3
            continue
        fi

        # Determine if INSERT line (active or commented)
        local is_commented=false
        local values=""

        if [[ "$line" == INSERT\ INTO\ app_registry\ VALUES\ \(* ]]; then
            values="${line#*VALUES (}"
            values="${values%);}"
        elif [[ "$line" == --INSERT\ INTO\ app_registry\ VALUES\ \(* ]]; then
            is_commented=true
            values="${line#*VALUES (}"
            values="${values%);}"
        else
            continue
        fi

        # Extract app_id and app_name (first two single-quoted fields)
        local rest="${values#\'}"
        local app_id="${rest%%\'*}"
        rest="${rest#*\', \'}"
        local app_name="${rest%%\'*}"

        # Extract launch_mode by matching known mode values
        local launch_mode="unknown"
        local mode=""
        for mode in multi single unique single_or_unique unknown; do
            if [[ "$values" == *"'${mode}'"* ]]; then
                launch_mode="$mode"
                break
            fi
        done

        local marker="✓"
        local suffix=""
        if [[ "$is_commented" == "true" ]]; then
            marker="○"
            suffix="  [commented out]"
            ((commented_count++)) || true
        else
            ((active_count++)) || true
        fi
        ((total_count++)) || true

        printf "  %s %-35s (%-20s) %-18s%s\n" \
            "$marker" "$app_id" "$app_name" "$launch_mode" "$suffix" >&3
    done < "$REGISTRY_SQL"

    echo "" >&3
    echo "Active: $active_count | Commented: $commented_count | Total: $total_count" >&3
}

# ============================================================================
# Main
# ============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: build-app-registry.sh <app_id>" >&2
        echo "       build-app-registry.sh --list" >&2
        exit 1
    fi

    local app_id="$1"

    # ================================================================
    # Phase 1: Validation & Setup
    # ================================================================

    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "  APP REGISTRY BUILDER" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3

    # Find .desktop file
    local desktop_file=""
    desktop_file=$(find_desktop_file "$app_id") || {
        print_error "No .desktop file found for: $app_id"
        print_info "Searched: ${DESKTOP_FILE_LOCATIONS[*]}"
        exit 1
    }
    print_success "Found: $desktop_file"

    # Extract display name
    local display_name=""
    display_name=$(extract_display_name "$desktop_file")
    if [[ -z "$display_name" ]]; then
        print_error "Could not extract Name= from .desktop file"
        exit 1
    fi
    print_info "Display name: $display_name"

    # Check existing entry
    local existing_status=""
    existing_status=$(check_existing_entry "$app_id")
    if [[ -n "$existing_status" ]]; then
        echo "" >&3
        print_warning "Entry already exists (${existing_status}):"
        echo "  $(get_existing_line "$app_id")" >&3
        echo "" >&3
        echo "  [U] Update (replace existing entry)" >&3
        echo "  [A] Abort" >&3
        echo "" >&3

        local choice=""
        read -r -p "Choice: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        if [[ "$choice" != "u" ]]; then
            print_info "Aborted."
            exit 0
        fi
    fi

    # Derive and confirm app_name
    local app_name=""
    app_name=$(derive_app_name "$display_name")

    confirm_field "app_name" "$app_name" "false"
    app_name="$CONFIRM_RESULT"

    # ================================================================
    # Phases 2-4 (loop on "Retry all")
    # ================================================================

    local retry_all="true"
    while [[ "$retry_all" == "true" ]]; do
        retry_all="false"

        # ============================================================
        # Phase 2: Launch & Detect Core Metadata
        # ============================================================

        echo "" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "  LAUNCHING APPLICATION" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3

        # Scan existing windows (snapshot for process-of-elimination)
        print_info "Scanning existing windows..."
        auto_detect_windows

        # Launch app and time it
        local launch_start_ms=""
        launch_start_ms=$(date +%s%3N)

        print_info "Launching $display_name..."
        (gtk-launch "$app_id" &>/dev/null &)

        # Wait for window via POE with retry (30s timeout)
        print_info "Waiting for window (timeout: 30s)..."
        local detected_uuid=""
        detected_uuid=$(get_uuid_by_process_of_elimination_with_retry "" 30000 100) || {
            print_error "Window not detected within 30 seconds."
            print_info "The app may have failed to launch or is already running."
            exit 1
        }

        print_success "Window detected"
        LAUNCHED_UUIDS+=("$detected_uuid")

        # Stability check — detect splash windows
        print_info "Checking for splash windows..."
        local stability_result=""
        local splash_detected="false"
        local splash_duration_ms=""
        stability_result=$(wait_for_stable_window "$detected_uuid" 20000 1000 10 0) || true

        if [[ -n "$stability_result" ]]; then
            local final_uuid=""
            IFS='|' read -r final_uuid splash_detected splash_duration_ms <<< "$stability_result"
            if [[ -n "$final_uuid" && "$final_uuid" != "$detected_uuid" ]]; then
                LAUNCHED_UUIDS+=("$final_uuid")
                detected_uuid="$final_uuid"
            fi
        fi

        # Record total launch time (including splash detection)
        local launch_time_ms=""
        launch_time_ms=$(( $(date +%s%3N) - launch_start_ms ))

        if [[ "$splash_detected" == "true" ]]; then
            print_success "Splash window detected (duration: ${splash_duration_ms}ms, total: ${launch_time_ms}ms)"
        else
            print_info "No splash window detected (${launch_time_ms}ms)"
        fi

        # Minimize the window (keep alive for metadata gathering)
        minimize_window "$detected_uuid"

        # ============================================================
        # Phase 3: Field-by-Field Confirmation
        # ============================================================

        echo "" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "  METADATA DETECTION" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3

        # --- Field 1: app_class ---
        local app_class=""
        while true; do
            app_class=$(get_window_class "$detected_uuid" 2>/dev/null) || app_class=""
            confirm_field "app_class" "$app_class"
            if [[ "$CONFIRM_RESULT" == "RETRY" ]]; then
                continue
            fi
            app_class="$CONFIRM_RESULT"
            break
        done

        # --- Field 2: has_splash_window ---
        local has_splash_window="$splash_detected"
        confirm_splash_field "$has_splash_window"
        has_splash_window="$CONFIRM_RESULT"

        # --- Field 3: supports_pid_validation ---
        local supports_pid=0
        local process_name=""
        while true; do
            local pid=""
            pid=$(get_window_pid "$detected_uuid" 2>/dev/null) || pid=""

            if [[ -n "$pid" ]]; then
                process_name=$(get_process_name "$pid" 2>/dev/null) || process_name=""
                if [[ -n "$process_name" ]]; then
                    supports_pid=1
                fi
            fi

            local pid_display="No"
            if [[ "$supports_pid" -eq 1 ]]; then
                pid_display="Yes (PID: ${pid}, process: ${process_name})"
            fi

            confirm_field "supports_pid_validation" "$pid_display"
            if [[ "$CONFIRM_RESULT" == "RETRY" ]]; then
                supports_pid=0
                process_name=""
                continue
            fi
            # Parse edited value
            if [[ "$CONFIRM_RESULT" == "No"* || "$CONFIRM_RESULT" == "0" || "$CONFIRM_RESULT" == "false" ]]; then
                supports_pid=0
                process_name=""
            elif [[ "$CONFIRM_RESULT" == "Yes"* || "$CONFIRM_RESULT" == "1" || "$CONFIRM_RESULT" == "true" ]]; then
                supports_pid=1
            fi
            break
        done

        # --- Field 4: process_name ---
        if [[ "$supports_pid" -eq 1 && -n "$process_name" ]]; then
            while true; do
                confirm_field "process_name" "$process_name"
                if [[ "$CONFIRM_RESULT" == "RETRY" ]]; then
                    local retry_pid=""
                    retry_pid=$(get_window_pid "$detected_uuid" 2>/dev/null) || retry_pid=""
                    if [[ -n "$retry_pid" ]]; then
                        process_name=$(get_process_name "$retry_pid" 2>/dev/null) || process_name=""
                    fi
                    continue
                fi
                process_name="$CONFIRM_RESULT"
                break
            done
        else
            process_name=""
            if [[ "$supports_pid" -eq 0 ]]; then
                echo "" >&3
                print_info "Skipping process_name (PID validation not supported)"
            fi
        fi

        # --- Field 5: window_title_pattern ---
        local window_title_pattern=""
        local current_title=""
        current_title=$(get_window_title "$detected_uuid" 2>/dev/null) || current_title=""
        if [[ -n "$current_title" ]]; then
            select_title_pattern "$current_title"
            window_title_pattern="$CONFIRM_RESULT"
        else
            echo "" >&3
            print_warning "Could not get window title — skipping title pattern"
        fi

        # --- Field 6: launch_mode ---
        local launch_mode=""
        while true; do
            echo "" >&3
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
            echo "  launch_mode" >&3
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
            echo "" >&3

            # Calculate timeout (1.5x launch time, 3s floor)
            local timeout_ms=0
            if [[ "$launch_time_ms" -gt 0 ]]; then
                timeout_ms=$(( (launch_time_ms * 3) / 2 ))
                [[ "$timeout_ms" -lt 3000 ]] && timeout_ms=3000
            else
                timeout_ms=10000
            fi

            print_info "Testing multi-instance support (timeout: $(( timeout_ms / 1000 ))s)..."

            # Refresh DB before second launch
            auto_detect_windows

            # Launch second instance
            (gtk-launch "$app_id" &>/dev/null &)

            local second_uuid=""
            second_uuid=$(get_uuid_by_process_of_elimination_with_retry "$app_class" "$timeout_ms" 100) || true

            # If splash app, verify second window stability
            if [[ -n "$second_uuid" && "$has_splash_window" == "true" ]]; then
                print_info "Splash app — verifying second window stability..."
                local splash_wait=""
                if [[ -n "$splash_duration_ms" && "$splash_duration_ms" -gt 0 ]]; then
                    splash_wait=$(( splash_duration_ms * 2 + 5000 ))
                else
                    splash_wait=15000
                fi

                local stab_result=""
                stab_result=$(wait_for_stable_window "$second_uuid" "$splash_wait" 500 3 "${splash_duration_ms:-0}") || true

                if [[ -n "$stab_result" ]]; then
                    local stable_uuid=""
                    IFS='|' read -r stable_uuid _ _ <<< "$stab_result"
                    if [[ -n "$stable_uuid" ]]; then
                        second_uuid="$stable_uuid"
                    else
                        second_uuid=""
                    fi
                else
                    second_uuid=""
                fi
            fi

            if [[ -n "$second_uuid" ]]; then
                launch_mode="multi"
                LAUNCHED_UUIDS+=("$second_uuid")

                # PID cross-check: shared PID means PID validation is unreliable
                local first_pid="" second_pid=""
                first_pid=$(get_window_pid "$detected_uuid" 2>/dev/null) || true
                second_pid=$(get_window_pid "$second_uuid" 2>/dev/null) || true

                if [[ -n "$first_pid" && -n "$second_pid" && "$first_pid" == "$second_pid" ]]; then
                    echo "" >&3
                    print_warning "Both windows share PID $first_pid — overriding supports_pid_validation to 0"
                    supports_pid=0
                    process_name=""
                fi

                # Close second window
                close_window "$second_uuid"
                local -a new_uuids=()
                local u=""
                for u in "${LAUNCHED_UUIDS[@]}"; do
                    [[ "$u" != "$second_uuid" ]] && new_uuids+=("$u")
                done
                LAUNCHED_UUIDS=("${new_uuids[@]}")
            else
                launch_mode="single_or_unique"
            fi

            echo "" >&3
            echo "  Detected: $launch_mode" >&3
            echo "" >&3
            echo "  [C] Confirm" >&3
            echo "  [R] Retry" >&3
            echo "  [E] Edit (enter manually)" >&3
            echo "" >&3

            local lm_choice=""
            read -r -p "Choice: " lm_choice
            lm_choice=$(echo "$lm_choice" | tr '[:upper:]' '[:lower:]')

            case "$lm_choice" in
                c|"") break ;;
                r) continue ;;
                e)
                    read -r -p "Enter launch_mode (multi/single/unique/single_or_unique): " launch_mode
                    break
                    ;;
                *) break ;;
            esac
        done

        # ============================================================
        # Phase 4: Summary & Output
        # ============================================================

        while true; do
            echo "" >&3
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
            echo "  SUMMARY" >&3
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
            echo "" >&3
            printf "  %-28s %s\n" "app_id:" "$app_id" >&3
            printf "  %-28s %s\n" "app_name:" "$app_name" >&3
            printf "  %-28s %s\n" "app_class:" "$app_class" >&3
            printf "  %-28s %s\n" "window_title_pattern:" "${window_title_pattern:-(none)}" >&3
            printf "  %-28s %s\n" "launch_mode:" "$launch_mode" >&3
            printf "  %-28s %s\n" "supports_pid_validation:" "$supports_pid" >&3
            printf "  %-28s %s\n" "process_name:" "${process_name:-(none)}" >&3
            printf "  %-28s %s\n" "has_splash_window:" "$has_splash_window" >&3
            echo "" >&3

            # Build INSERT statement
            local insert_line=""
            insert_line="INSERT INTO app_registry VALUES ('${app_id}', '${app_name}', '${app_class}', '${window_title_pattern}', '${launch_mode}', ${supports_pid}, '${process_name}', '${has_splash_window}');"

            echo "  INSERT:" >&3
            echo "  ${insert_line}" >&3
            echo "" >&3
            echo "  [W] Write to app-registry.sql" >&3
            echo "  [E] Edit a field" >&3
            echo "  [R] Retry all (restart from launch)" >&3
            echo "  [A] Abort" >&3
            echo "" >&3

            local summary_choice=""
            read -r -p "Choice: " summary_choice
            summary_choice=$(echo "$summary_choice" | tr '[:upper:]' '[:lower:]')

            case "$summary_choice" in
                w)
                    # --- Write to file ---
                    if [[ -n "$existing_status" ]]; then
                        write_registry_entry "$app_id" "$insert_line" "replace"
                        print_success "Updated entry for $app_id"
                    else
                        # New entry — select category placement
                        echo "" >&3
                        echo "  Select category:" >&3
                        echo "" >&3

                        local -a categories=()
                        mapfile -t categories < <(parse_registry_categories)

                        local ci=1
                        local cat_entry=""
                        for cat_entry in "${categories[@]}"; do
                            echo "  [$ci] ${cat_entry#*|}" >&3
                            ((ci++))
                        done
                        echo "  [$ci] End of file" >&3
                        local end_option=$ci
                        echo "" >&3

                        local cat_choice=""
                        read -r -p "Category: " cat_choice

                        if [[ "$cat_choice" =~ ^[0-9]+$ && "$cat_choice" -ge 1 && "$cat_choice" -le "$end_option" ]]; then
                            if [[ "$cat_choice" -eq "$end_option" ]]; then
                                write_registry_entry "$app_id" "$insert_line" "append"
                            else
                                local cat_idx=$((cat_choice - 1))
                                local cat_line="${categories[$cat_idx]%%|*}"
                                local last_line=""
                                last_line=$(find_category_last_insert "$cat_line")
                                write_registry_entry "$app_id" "$insert_line" "insert" "$last_line"
                            fi
                        else
                            write_registry_entry "$app_id" "$insert_line" "append"
                        fi
                        print_success "Added entry for $app_id"
                    fi

                    echo "" >&3
                    echo "  Written: ${insert_line}" >&3
                    echo "" >&3

                    close_launched_windows
                    return 0
                    ;;
                e)
                    # --- Edit a specific field ---
                    echo "" >&3
                    echo "  Select field to edit:" >&3
                    echo "  [1] app_name (${app_name})" >&3
                    echo "  [2] app_class (${app_class})" >&3
                    echo "  [3] window_title_pattern (${window_title_pattern:-(none)})" >&3
                    echo "  [4] launch_mode (${launch_mode})" >&3
                    echo "  [5] supports_pid_validation (${supports_pid})" >&3
                    echo "  [6] process_name (${process_name:-(none)})" >&3
                    echo "  [7] has_splash_window (${has_splash_window})" >&3
                    echo "" >&3

                    local field_choice=""
                    read -r -p "Field: " field_choice

                    case "$field_choice" in
                        1) read -r -p "app_name: " app_name ;;
                        2) read -r -p "app_class: " app_class ;;
                        3)
                            if [[ -n "$current_title" ]]; then
                                select_title_pattern "$current_title"
                                window_title_pattern="$CONFIRM_RESULT"
                            else
                                read -r -p "window_title_pattern: " window_title_pattern
                            fi
                            ;;
                        4) read -r -p "launch_mode (multi/single/unique/single_or_unique): " launch_mode ;;
                        5) read -r -p "supports_pid_validation (0/1): " supports_pid ;;
                        6) read -r -p "process_name: " process_name ;;
                        7) read -r -p "has_splash_window (true/false): " has_splash_window ;;
                        *) print_error "Invalid field number." ;;
                    esac
                    continue
                    ;;
                r)
                    # --- Retry all ---
                    close_launched_windows
                    retry_all="true"
                    break
                    ;;
                a)
                    print_info "Aborted."
                    close_launched_windows
                    return 0
                    ;;
                *)
                    print_error "Invalid choice."
                    continue
                    ;;
            esac
        done
    done
}

# ============================================================================
# Entry Point
# ============================================================================

# Handle --list before DB startup (no DB needed)
if [[ $# -gt 0 && "$1" == "--list" ]]; then
    list_registry
    exit 0
fi

# Check minimum dependencies for interactive mode
for cmd in kdotool gtk-launch; do
    if ! command -v "$cmd" &>/dev/null; then
        print_error "Required command not found: $cmd"
        exit 1
    fi
done

# Start database server (needed for window tracking during detection)
db_server_start

# Cleanup trap — close launched windows and stop DB on exit
cleanup() {
    local exit_code=$?
    close_launched_windows 2>/dev/null || true
    db_server_stop 2>/dev/null || true
    exit "$exit_code"
}
trap cleanup EXIT SIGINT SIGTERM

main "$@"
