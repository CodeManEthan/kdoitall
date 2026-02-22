#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_MINIMIZE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"
# shellcheck source=../../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"

workspace_minimize() {
    local workspace_name="$1"
    local function_name="workspace_minimize"

    debug_function_enter "$function_name" "$@"

    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        echo "Usage: kdoitall workspace minimize <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Check if workspace exists in database
    if ! db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Check if workspace is active
    local is_active=""
    is_active=$(db_get_workspace_is_active "$workspace_name")

    if [[ "$is_active" != "1" ]]; then
        echo "Workspace '$workspace_name' is not active. Nothing to minimize." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Get tracked windows for the workspace
    local -a window_rows=()
    mapfile -t window_rows < <(db_get_workspace_windows_ordered "$workspace_name")

    if [[ ${#window_rows[@]} -eq 0 || -z "${window_rows[0]}" ]]; then
        echo "No tracked windows found for workspace '$workspace_name'." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Refresh current windows for existence checks
    refresh_current_windows

    # Minimize all live windows
    local window_name=""
    local uuid=""
    local minimized_count=0

    for row in "${window_rows[@]}"; do
        IFS='|' read -r window_name uuid <<< "$row"

        if window_exists "$uuid"; then
            minimize_window "$uuid"
            ((minimized_count++)) || true
            debug_log "$function_name" "Minimized window: $window_name ($uuid)"
        else
            debug_log "$function_name" "Skipping stale window: $window_name ($uuid)"
        fi
    done

    if [[ $minimized_count -eq 0 ]]; then
        echo "No live windows found for workspace '$workspace_name'." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    info_log "$function_name" "Workspace '$workspace_name' minimized ($minimized_count window(s))"
    debug_function_exit "$function_name"
    return 0
}
