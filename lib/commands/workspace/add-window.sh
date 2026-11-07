#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_ADD_WINDOW_LOADED" || return 0

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

workspace_add_window_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall workspace add-window <workspace-name> [options]

Required flags:
  --name, -n <name>         Window name (unique across all workspaces)
  --app, -a <app_id>        Application ID (from 'kdoitall app list')
  --desktop, -d <number>    Desktop number
  --screen, -s <ref>        Screen number, name, or alias
  --position, -p <pos>      Position (name, abbreviation, or display name)

Optional flags:
  --function, -f <func>     Launch function (default: launch_by_app_id)
  --params <params>         Launch parameters

Examples:
  kdoitall workspace add-window dev-env \
    --name dev-firefox --app org.mozilla.firefox \
    --desktop 1 --screen 1 --position fs

  kdoitall ws aw dev-env \
    -n dev-code -a code -f launch_code_window \
    -d 1 -s 2 -p lh --params "/home/user/project"

EOF
}

workspace_add_window() {
    local function_name="workspace_add_window"
    local workspace_name=""
    local window_name=""
    local app_id=""
    local desktop=""
    local screen=""
    local position=""
    local launch_function=""
    local parameters=""

    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()

    debug_function_enter "$function_name" "$@"

    # ──────────────────────────────────────────────
    # Parse arguments
    # ──────────────────────────────────────────────

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name|-n)
                if [[ -n "${2:-}" ]]; then
                    window_name="$2"
                    shift 2
                else
                    echo "Error: --name requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --app|-a)
                if [[ -n "${2:-}" ]]; then
                    app_id="$2"
                    shift 2
                else
                    echo "Error: --app requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --desktop|-d)
                if [[ -n "${2:-}" ]]; then
                    desktop="$2"
                    shift 2
                else
                    echo "Error: --desktop requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --screen|-s)
                if [[ -n "${2:-}" ]]; then
                    screen="$2"
                    shift 2
                else
                    echo "Error: --screen requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --position|-p)
                if [[ -n "${2:-}" ]]; then
                    position="$2"
                    shift 2
                else
                    echo "Error: --position requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --function|-f)
                if [[ -n "${2:-}" ]]; then
                    launch_function="$2"
                    shift 2
                else
                    echo "Error: --function requires a value" >&2
                    debug_function_exit "$function_name"
                    return "$ERR_MISSING_PARAMETER"
                fi
                ;;
            --params)
                # Allow empty params value
                shift
                parameters="${1:-}"
                shift
                ;;
            --help|-h)
                workspace_add_window_show_help
                debug_function_exit "$function_name"
                return 0
                ;;
            *)
                if [[ -z "$workspace_name" ]]; then
                    workspace_name="$1"
                    shift
                else
                    echo "Error: Unknown argument: $1" >&2
                    workspace_add_window_show_help
                    debug_function_exit "$function_name"
                    return 1
                fi
                ;;
        esac
    done

    # Default launch function
    if [[ -z "$launch_function" ]]; then
        launch_function="launch_by_app_id"
    fi

    # ──────────────────────────────────────────────
    # Validate workspace
    # ──────────────────────────────────────────────

    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name is required." >&2
        echo "Usage: kdoitall workspace add-window <workspace-name> [options]" >&3
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

    # ──────────────────────────────────────────────
    # Validate required flags
    # ──────────────────────────────────────────────

    local missing=()
    [[ -z "$window_name" ]] && missing+=("--name")
    [[ -z "$app_id" ]] && missing+=("--app")
    [[ -z "$desktop" ]] && missing+=("--desktop")
    [[ -z "$screen" ]] && missing+=("--screen")
    [[ -z "$position" ]] && missing+=("--position")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required flags: ${missing[*]}" >&2
        workspace_add_window_show_help
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    # ──────────────────────────────────────────────
    # Validate each field
    # ──────────────────────────────────────────────

    # Window name format
    if ! validate_window_name "$window_name"; then
        debug_function_exit "$function_name"
        return "$ERR_INVALID_WINDOW_NAME"
    fi

    # Window name global uniqueness
    if db_window_definition_exists "$window_name"; then
        local existing_def=""
        existing_def=$(db_get_window_definition "$window_name" 2>/dev/null)
        local existing_workspace=""
        existing_workspace=$(echo "$existing_def" | cut -d'|' -f2)
        echo "Error: Window name '$window_name' is already in use by workspace '$existing_workspace'." >&2
        debug_function_exit "$function_name"
        return "$ERR_INVALID_WINDOW_NAME"
    fi

    # App exists
    if ! db_application_exists "$app_id"; then
        echo "Error: Application '$app_id' not found. Run 'kdoitall app scan' first." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Launch function validation
    if [[ "$launch_function" != "launch_by_app_id" ]]; then
        local launch_opts=""
        launch_opts=$(db_get_launch_options "$app_id")
        if ! launch_option_exists "$launch_opts" "$launch_function"; then
            echo "Error: Launch function '$launch_function' not found for app '$app_id'." >&2
            echo "Available functions: $(echo "$launch_opts" | cut -d'|' -f1 | tr '\n' ', ')" >&3
            debug_function_exit "$function_name"
            return 1
        fi
    fi

    # Params validation
    if ! validate_params "$parameters"; then
        echo "Error: --params must not contain '|', a newline or other control characters (tabs separate values)." >&2
        debug_function_exit "$function_name"
        return "$ERR_INVALID_PARAMETER"
    fi

    # Desktop validation
    if ! validate_desktop_number "$desktop" > /dev/null; then
        echo "Error: Desktop '$desktop' is not valid (must be 1-$DETECTED_DESKTOP_COUNT)." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Screen resolution
    local resolved_screen=""
    if ! resolved_screen=$(resolve_screen_reference "$screen" 2>/dev/null); then
        echo "Error: Screen '$screen' is not valid." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Position resolution
    local resolved_position=""
    if ! resolved_position=$(resolve_position_reference "$position" 2>/dev/null); then
        echo "Error: Position '$position' is not valid. Use a position name (FULLSCREEN), abbreviation (fs), or display name (Fullscreen)." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # ──────────────────────────────────────────────
    # Add window and regenerate
    # ──────────────────────────────────────────────

    # Load existing window definitions
    if ! load_workspace_apps_array "$workspace_name"; then
        echo "Error: Failed to load existing window definitions." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Append new window
    WORKSPACE_APPS+=("${app_id}|${window_name}|${launch_function}|${desktop}|${resolved_screen}|${resolved_position}|${parameters}")

    # Regenerate workspace scripts
    if ! generate_workspace_scripts "$workspace_name"; then
        echo "Error: Failed to regenerate workspace scripts." >&2
        debug_function_exit "$function_name"
        return "$ERR_SCRIPT_GENERATION_FAILED"
    fi

    echo "" >&3
    print_success "Window '$window_name' added to workspace '$workspace_name'"
    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}
