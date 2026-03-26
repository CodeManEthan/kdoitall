#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_REMOVE_WINDOW_LOADED" || return 0

# shellcheck source=../../workspace/generator.sh
source "${LIB_DIR}/workspace/generator.sh"
# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/window-definitions.sh
source "${LIB_DIR}/db/window-definitions.sh"
# shellcheck source=../../utils/workspace-validators.sh
source "${LIB_DIR}/utils/workspace-validators.sh"
# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"

workspace_remove_window_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall workspace remove-window <workspace-name> <window-name>

Remove a window definition from a workspace. The workspace must have
at least one window remaining after removal.

If the removed window was the focus window, focus is cleared.

Examples:
  kdoitall workspace remove-window dev-env dev-firefox
  kdoitall ws rw dev-env dev-firefox

EOF
}

workspace_remove_window() {
    local function_name="workspace_remove_window"
    local workspace_name=""
    local window_name=""

    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()

    debug_function_enter "$function_name" "$@"

    # ──────────────────────────────────────────────
    # Parse arguments
    # ──────────────────────────────────────────────

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                workspace_remove_window_show_help
                debug_function_exit "$function_name"
                return 0
                ;;
            -*)
                echo "Error: Unknown flag: $1" >&2
                workspace_remove_window_show_help
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                if [[ -z "$workspace_name" ]]; then
                    workspace_name="$1"
                elif [[ -z "$window_name" ]]; then
                    window_name="$1"
                else
                    echo "Error: Too many arguments." >&2
                    workspace_remove_window_show_help
                    debug_function_exit "$function_name"
                    return 1
                fi
                shift
                ;;
        esac
    done

    # ──────────────────────────────────────────────
    # Validate workspace
    # ──────────────────────────────────────────────

    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name is required." >&2
        echo "Usage: kdoitall workspace remove-window <workspace-name> <window-name>" >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    if [[ -z "$window_name" ]]; then
        echo "Error: Window name is required." >&2
        echo "Usage: kdoitall workspace remove-window <workspace-name> <window-name>" >&3
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
    # Validate window exists in this workspace
    # ──────────────────────────────────────────────

    if ! db_window_definition_exists "$window_name"; then
        echo "Error: Window '$window_name' not found." >&2
        debug_function_exit "$function_name"
        return "$ERR_WINDOW_DEFINITION_NOT_FOUND"
    fi

    local existing_def=""
    existing_def=$(db_get_window_definition "$window_name")
    local existing_workspace=""
    existing_workspace=$(echo "$existing_def" | cut -d'|' -f2)

    if [[ "$existing_workspace" != "$workspace_name" ]]; then
        echo "Error: Window '$window_name' belongs to workspace '$existing_workspace', not '$workspace_name'." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # ──────────────────────────────────────────────
    # Check minimum window count
    # ──────────────────────────────────────────────

    # Load all window definitions
    if ! load_workspace_apps_array "$workspace_name"; then
        echo "Error: Failed to load window definitions." >&2
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ ${#WORKSPACE_APPS[@]} -le 1 ]]; then
        echo "Error: Cannot remove the last window from workspace '$workspace_name'." >&2
        echo "Delete the workspace instead with: kdoitall workspace delete $workspace_name" >&3
        debug_function_exit "$function_name"
        return "$ERR_NO_APPLICATIONS"
    fi

    # ──────────────────────────────────────────────
    # Remove window and regenerate
    # ──────────────────────────────────────────────

    # Find and remove the matching entry
    local idx=0
    for idx in "${!WORKSPACE_APPS[@]}"; do
        local entry_window_name=""
        entry_window_name=$(echo "${WORKSPACE_APPS[$idx]}" | cut -d'|' -f2)
        if [[ "$entry_window_name" == "$window_name" ]]; then
            unset 'WORKSPACE_APPS[idx]'
            break
        fi
    done

    # Re-index to close the gap
    WORKSPACE_APPS=("${WORKSPACE_APPS[@]}")

    # Clear focus_window if it was the removed window
    local focus_window=""
    focus_window=$(db_get_workspace_focus_window "$workspace_name")
    if [[ "$focus_window" == "$window_name" ]]; then
        db_set_workspace_focus_window "$workspace_name" ""
        print_info "Focus window cleared (was set to removed window '$window_name')."
    fi

    # Regenerate workspace scripts
    if ! generate_workspace_scripts "$workspace_name"; then
        echo "Error: Failed to regenerate workspace scripts." >&2
        debug_function_exit "$function_name"
        return "$ERR_SCRIPT_GENERATION_FAILED"
    fi

    echo "" >&3
    print_success "Window '$window_name' removed from workspace '$workspace_name'"
    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}
