#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_OPEN_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../../db/window-definitions.sh
source "${LIB_DIR}/db/window-definitions.sh"

window_open() {
    local window_name="$1"
    local function_name="window_open"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$window_name" ]]; then
        echo "Usage: kdoitall window open <window-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Check if window is already tracked and still alive
    local existing_uuid=""
    existing_uuid=$(db_get_uuid "$window_name" 2>/dev/null) || true

    if [[ -n "$existing_uuid" ]]; then
        # UUID exists in app_windows — check if window is still alive
        if kdotool getwindowname "$existing_uuid" &>/dev/null; then
            echo "Error: Window '$window_name' is already open" >&3
            debug_error "$function_name" "$ERR_WINDOW_ALREADY_OPEN" "$window_name"
            debug_function_exit "$function_name"
            return 1
        fi

        # Window is dead — clean up stale entry before re-launching
        debug_log "$function_name" "Cleaning up stale app_windows entry for '$window_name'"
        db_delete_window "$window_name"
    fi

    # Look up launch configuration from window_definitions
    local definition=""
    definition=$(db_get_window_definition "$window_name")
    if [[ -z "$definition" ]]; then
        echo "Error: No window definition found for '$window_name'" >&3
        echo "This window may have been created before window definitions were supported." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Parse the pipe-separated definition
    local def_window_name def_workspace def_app_id def_launch_function
    local def_desktop def_screen def_position def_parameters def_display_order
    IFS='|' read -r def_window_name def_workspace def_app_id def_launch_function \
        def_desktop def_screen def_position def_parameters def_display_order <<< "$definition"

    debug_log "$function_name" "Re-launching '$window_name': app=$def_app_id, func=$def_launch_function, desktop=$def_desktop, screen=$def_screen, position=$def_position"

    echo "Re-opening window: $window_name" >&3

    # Re-launch based on launch function type
    if [[ "$def_launch_function" == "launch_by_app_id" ]]; then
        # Desktop launch — use the existing launch_by_app_id function
        launch_by_app_id "$def_workspace" "$def_window_name" "$def_app_id" \
            "$def_desktop" "$def_screen" "$def_position"
    elif [[ "$def_launch_function" == terminal_* ]]; then
        # Shared terminal function — source shared functions file
        # shellcheck source=/dev/null
        source "${LIB_DIR}/app-definitions/shared/terminal-emulator/functions.sh"

        # Split tab-delimited parameters into an array
        local -a param_args=()
        if [[ -n "$def_parameters" ]]; then
            IFS=$'\t' read -ra param_args <<< "$def_parameters"
        fi

        # Call with app_id + individual parameters
        "$def_launch_function" "$def_workspace" "$def_window_name" "$def_app_id" \
            "$def_desktop" "$def_screen" "$def_position" "${param_args[@]}"
    else
        # Per-app terminal launch — source the app's functions file and call directly
        local app_directory_path=""
        app_directory_path=$(db_get_app_directory_path "$def_app_id")

        if [[ -n "$app_directory_path" && -f "${app_directory_path}/functions.sh" ]]; then
            # shellcheck source=/dev/null
            source "${app_directory_path}/functions.sh"
        fi

        # Call the custom launch function with appropriate arguments
        if [[ -n "$def_parameters" ]]; then
            "$def_launch_function" "$def_workspace" "$def_window_name" \
                "$def_desktop" "$def_screen" "$def_position" "$def_parameters"
        else
            "$def_launch_function" "$def_workspace" "$def_window_name" \
                "$def_desktop" "$def_screen" "$def_position" ""
        fi
    fi

    echo "Window '$window_name' re-opened" >&3
    debug_function_exit "$function_name"
    return 0
}
