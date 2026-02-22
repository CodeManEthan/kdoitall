#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_FOCUS_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"
# shellcheck source=../../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"

workspace_focus() {
    local workspace_name="$1"
    local function_name="workspace_focus"

    debug_function_enter "$function_name" "$@"

    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        echo "Usage: kdoitall workspace focus <workspace-name>" >&3
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
        echo "Workspace '$workspace_name' is not active. Open it first with 'workspace open'." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Get tracked windows ordered by display_order
    local -a window_rows=()
    mapfile -t window_rows < <(db_get_workspace_windows_ordered "$workspace_name")

    if [[ ${#window_rows[@]} -eq 0 || -z "${window_rows[0]}" ]]; then
        echo "No tracked windows found for workspace '$workspace_name'." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Refresh current windows for existence checks
    refresh_current_windows

    # Raise all windows in display_order and track the last valid UUID
    local window_name=""
    local uuid=""
    local last_valid_uuid=""
    local last_valid_name=""

    for row in "${window_rows[@]}"; do
        IFS='|' read -r window_name uuid <<< "$row"

        if window_exists "$uuid"; then
            raise_window "$uuid"
            last_valid_uuid="$uuid"
            last_valid_name="$window_name"
            debug_log "$function_name" "Raised window: $window_name ($uuid)"
        else
            debug_log "$function_name" "Skipping stale window: $window_name ($uuid)"
        fi
    done

    if [[ -z "$last_valid_uuid" ]]; then
        echo "No live windows found for workspace '$workspace_name'." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Determine activation target
    local activate_uuid=""
    local focus_window=""
    focus_window=$(db_get_workspace_focus_window "$workspace_name")

    if [[ -n "$focus_window" ]]; then
        local focus_uuid=""
        focus_uuid=$(db_get_window_uuid_by_name "$focus_window")

        if [[ -n "$focus_uuid" ]] && window_exists "$focus_uuid"; then
            activate_uuid="$focus_uuid"
            debug_log "$function_name" "Activating focus window: $focus_window ($focus_uuid)"
        else
            debug_log "$function_name" "Focus window '$focus_window' not found or stale, falling back to last window"
            activate_uuid="$last_valid_uuid"
        fi
    else
        activate_uuid="$last_valid_uuid"
        debug_log "$function_name" "No focus window set, activating last window: $last_valid_name ($last_valid_uuid)"
    fi

    activate_window "$activate_uuid"

    info_log "$function_name" "Workspace '$workspace_name' focused"
    debug_function_exit "$function_name"
    return 0
}
