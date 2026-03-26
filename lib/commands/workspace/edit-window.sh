#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_EDIT_WINDOW_LOADED" || return 0

# shellcheck source=../../workspace/generator.sh
source "${LIB_DIR}/workspace/generator.sh"
# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../../db/window-definitions.sh
source "${LIB_DIR}/db/window-definitions.sh"
# shellcheck source=../../utils/workspace-validators.sh
source "${LIB_DIR}/utils/workspace-validators.sh"
# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../../window-management/desktop.sh
source "${LIB_DIR}/window-management/desktop.sh"

workspace_edit_window_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall workspace edit-window <workspace-name> <window-name> [options]

At least one option is required. Only specified fields are changed.

Options:
  --name, -n <name>              Rename the window
  --desktop, -d <number>         Change desktop number
  --screen, -s <ref>             Change screen (number, name, or alias)
  --position, -p <pos>           Change position (name, abbreviation, or display name)
  --function, -f <func>          Change launch function (must exist for current app)
  --params <params>              Change launch parameters
  --display-order <number>       Change display order (0-based)

Note: To change the application, remove the window and add a new one.

Examples:
  kdoitall workspace edit-window dev-env dev-firefox --desktop 2 --position lh
  kdoitall ws ew dev-env dev-firefox --name dev-browser
  kdoitall ws ew dev-env dev-code --display-order 0

EOF
}

workspace_edit_window() {
    local function_name="workspace_edit_window"
    local workspace_name=""
    local window_name=""
    local new_window_name=""
    local new_desktop=""
    local new_screen=""
    local new_position=""
    local new_function=""
    local new_params=""
    local has_params_flag=false
    local new_display_order=""
    local has_flags=false

    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()

    debug_function_enter "$function_name" "$@"

    # ──────────────────────────────────────────────
    # Parse arguments
    # ──────────────────────────────────────────────

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)
                has_flags=true
                if [[ -n "${2:-}" ]]; then
                    new_window_name="$2"
                    shift 2
                else
                    echo "Error: --name requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --desktop|-d)
                has_flags=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    new_desktop="$2"
                    shift 2
                else
                    echo "Error: --desktop requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --screen|-s)
                has_flags=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    new_screen="$2"
                    shift 2
                else
                    echo "Error: --screen requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --position|-p)
                has_flags=true
                if [[ -n "${2:-}" ]]; then
                    new_position="$2"
                    shift 2
                else
                    echo "Error: --position requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --function|-f)
                has_flags=true
                if [[ -n "${2:-}" ]]; then
                    new_function="$2"
                    shift 2
                else
                    echo "Error: --function requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --params)
                has_flags=true
                has_params_flag=true
                shift
                new_params="${1:-}"
                shift
                ;;
            --display-order)
                has_flags=true
                if [[ -n "${2:-}" ]]; then
                    new_display_order="$2"
                    shift 2
                else
                    echo "Error: --display-order requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --help|-h)
                workspace_edit_window_show_help
                debug_function_exit "$function_name"
                return 0
                ;;
            *)
                if [[ -z "$workspace_name" ]]; then
                    workspace_name="$1"
                elif [[ -z "$window_name" ]]; then
                    window_name="$1"
                else
                    echo "Error: Unknown argument: $1" >&2
                    workspace_edit_window_show_help
                    debug_function_exit "$function_name"
                    return 1
                fi
                shift
                ;;
        esac
    done

    # ──────────────────────────────────────────────
    # Validate workspace and window
    # ──────────────────────────────────────────────

    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name is required." >&2
        echo "Usage: kdoitall workspace edit-window <workspace-name> <window-name> [options]" >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    if [[ -z "$window_name" ]]; then
        echo "Error: Window name is required." >&2
        echo "Usage: kdoitall workspace edit-window <workspace-name> <window-name> [options]" >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    if ! db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' not found." >&2
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_NOT_FOUND"
    fi

    local is_active=""
    is_active=$(db_get_workspace_is_active "$workspace_name")
    if [[ "$is_active" == "1" ]]; then
        echo "Error: Cannot modify workspace '$workspace_name' while it is active." >&2
        echo "Close the workspace first with: kdoitall workspace close $workspace_name" >&3
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_IS_ACTIVE"
    fi

    if [[ "$has_flags" != true ]]; then
        echo "Error: At least one option is required." >&2
        echo "Use 'kdoitall workspace edit $workspace_name' for interactive editing." >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    # Verify window exists
    if ! db_window_definition_exists "$window_name"; then
        echo "Error: Window '$window_name' not found." >&2
        debug_function_exit "$function_name"
        return "$ERR_WINDOW_DEFINITION_NOT_FOUND"
    fi

    # Verify window belongs to this workspace
    local existing_def=""
    existing_def=$(db_get_window_definition "$window_name")
    local existing_workspace=""
    existing_workspace=$(echo "$existing_def" | cut -d'|' -f2)

    if [[ "$existing_workspace" != "$workspace_name" ]]; then
        echo "Error: Window '$window_name' belongs to workspace '$existing_workspace', not '$workspace_name'." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Parse existing definition
    local e_app_id=""
    local e_launch_function=""
    local e_desktop=""
    local e_screen=""
    local e_position=""
    local e_parameters=""
    IFS='|' read -r _ _ e_app_id e_launch_function e_desktop e_screen e_position e_parameters _ <<< "$existing_def"

    # ──────────────────────────────────────────────
    # Validate each provided flag
    # ──────────────────────────────────────────────

    local -a changes=()

    # --name: validate format and uniqueness
    if [[ -n "$new_window_name" ]]; then
        if [[ "$new_window_name" == "$window_name" ]]; then
            echo "Error: New window name is the same as the current name." >&2
            debug_function_exit "$function_name"
            return 1
        fi

        if ! validate_window_name "$new_window_name"; then
            debug_function_exit "$function_name"
            return "$ERR_INVALID_WINDOW_NAME"
        fi

        if db_window_definition_exists "$new_window_name"; then
            local conflict_def=""
            conflict_def=$(db_get_window_definition "$new_window_name" 2>/dev/null)
            local conflict_workspace=""
            conflict_workspace=$(echo "$conflict_def" | cut -d'|' -f2)
            echo "Error: Window name '$new_window_name' is already in use by workspace '$conflict_workspace'." >&2
            debug_function_exit "$function_name"
            return "$ERR_INVALID_WINDOW_NAME"
        fi

        changes+=("name: $window_name -> $new_window_name")
    fi

    # --desktop: validate range
    if [[ -n "$new_desktop" ]]; then
        if ! validate_desktop_number "$new_desktop" > /dev/null; then
            echo "Error: Desktop '$new_desktop' is not valid (must be 1-$DETECTED_DESKTOP_COUNT)." >&2
            debug_function_exit "$function_name"
            return 1
        fi
        changes+=("desktop: $e_desktop -> $new_desktop")
    fi

    # --screen: resolve reference
    local resolved_screen=""
    if [[ -n "$new_screen" ]]; then
        if ! resolved_screen=$(resolve_screen_reference "$new_screen" 2>/dev/null); then
            echo "Error: Screen '$new_screen' is not valid." >&2
            debug_function_exit "$function_name"
            return 1
        fi
        changes+=("screen: $e_screen -> $resolved_screen")
    fi

    # --position: resolve reference
    local resolved_position=""
    if [[ -n "$new_position" ]]; then
        if ! resolved_position=$(resolve_position_reference "$new_position" 2>/dev/null); then
            echo "Error: Position '$new_position' is not valid. Use a position name (FULLSCREEN), abbreviation (fs), or display name (Fullscreen)." >&2
            debug_function_exit "$function_name"
            return 1
        fi
        changes+=("position: $e_position -> $resolved_position")
    fi

    # --function: validate against app's launch options
    if [[ -n "$new_function" ]]; then
        if [[ "$new_function" != "launch_by_app_id" ]]; then
            local launch_opts=""
            launch_opts=$(db_get_launch_options "$e_app_id")
            if [[ -z "$launch_opts" ]] || ! echo "$launch_opts" | grep -q "^${new_function}|"; then
                echo "Error: Launch function '$new_function' not found for app '$e_app_id'." >&2
                debug_function_exit "$function_name"
                return 1
            fi
        fi
        changes+=("function: $e_launch_function -> $new_function")
    fi

    # --params: no validation needed
    if [[ "$has_params_flag" == true ]]; then
        changes+=("params: '${e_parameters}' -> '${new_params}'")
    fi

    # --display-order: validate non-negative integer
    if [[ -n "$new_display_order" ]]; then
        if ! [[ "$new_display_order" =~ ^[0-9]+$ ]]; then
            echo "Error: Display order must be a non-negative integer." >&2
            debug_function_exit "$function_name"
            return 1
        fi
        changes+=("display-order: -> $new_display_order")
    fi

    # ──────────────────────────────────────────────
    # Apply changes and regenerate
    # ──────────────────────────────────────────────

    # Load all window definitions
    if ! load_workspace_apps_array "$workspace_name"; then
        echo "Error: Failed to load window definitions." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Build the updated entry — override only provided fields
    local final_window_name="${new_window_name:-$window_name}"
    local final_desktop="${new_desktop:-$e_desktop}"
    local final_screen="${resolved_screen:-$e_screen}"
    local final_position="${resolved_position:-$e_position}"
    local final_function="${new_function:-$e_launch_function}"
    local final_params="$e_parameters"
    if [[ "$has_params_flag" == true ]]; then
        final_params="$new_params"
    fi

    # Find and replace the matching entry in WORKSPACE_APPS
    local idx=0
    local found=false
    for idx in "${!WORKSPACE_APPS[@]}"; do
        local entry_window_name=""
        entry_window_name=$(echo "${WORKSPACE_APPS[$idx]}" | cut -d'|' -f2)
        if [[ "$entry_window_name" == "$window_name" ]]; then
            WORKSPACE_APPS[$idx]="${e_app_id}|${final_window_name}|${final_function}|${final_desktop}|${final_screen}|${final_position}|${final_params}"
            found=true
            break
        fi
    done

    if [[ "$found" != true ]]; then
        echo "Error: Window '$window_name' not found in workspace apps array." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Handle display-order reordering
    if [[ -n "$new_display_order" ]]; then
        local entry="${WORKSPACE_APPS[$idx]}"
        unset 'WORKSPACE_APPS[idx]'
        WORKSPACE_APPS=("${WORKSPACE_APPS[@]}")

        # Clamp to valid range
        local max_idx=${#WORKSPACE_APPS[@]}
        if [[ "$new_display_order" -gt "$max_idx" ]]; then
            new_display_order="$max_idx"
        fi

        # Insert at new position
        local -a new_array=()
        local i=0
        local inserted=false
        for i in "${!WORKSPACE_APPS[@]}"; do
            if [[ $i -eq $new_display_order && "$inserted" != true ]]; then
                new_array+=("$entry")
                inserted=true
            fi
            new_array+=("${WORKSPACE_APPS[$i]}")
        done
        if [[ "$inserted" != true ]]; then
            new_array+=("$entry")
        fi
        WORKSPACE_APPS=("${new_array[@]}")
    fi

    # Update focus_window if the window was renamed and was the focus window
    if [[ -n "$new_window_name" ]]; then
        local focus_window=""
        focus_window=$(db_get_workspace_focus_window "$workspace_name")
        if [[ "$focus_window" == "$window_name" ]]; then
            db_set_workspace_focus_window "$workspace_name" "$new_window_name"
            print_info "Focus window updated to '$new_window_name'."
        fi
    fi

    # Regenerate workspace scripts
    if ! generate_workspace_scripts "$workspace_name"; then
        echo "Error: Failed to regenerate workspace scripts." >&2
        debug_function_exit "$function_name"
        return "$ERR_SCRIPT_GENERATION_FAILED"
    fi

    echo "" >&3
    print_success "Window '$window_name' updated in workspace '$workspace_name'"
    local change=""
    for change in "${changes[@]}"; do
        echo "  $change" >&3
    done
    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}
