#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_MOVE_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"

window_move() {
    local window_name="${1:-}"
    local screen_ref="${2:-}"
    local position="${3:-}"
    local function_name="window_move"
    local uuid=""

    debug_function_enter "$function_name" "$@"

    if [[ -z "$window_name" || -z "$screen_ref" || -z "$position" ]]; then
        echo "Usage: kdoitall window move <window-name> <screen> <position>" >&3
        echo "" >&3
        echo "Positions: Fullscreen, Right Half, Left Half, Top Half, Bottom Half," >&3
        echo "           Top Left, Top Right, Bottom Left, Bottom Right," >&3
        echo "           Left Third, Middle Third, Right Third" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Look up UUID from tracked windows
    uuid=$(db_get_uuid "$window_name")
    if [[ -z "$uuid" ]]; then
        echo "Error: Window '$window_name' not found in tracked windows" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Verify window is still alive
    if ! kdotool getwindowname "$uuid" &>/dev/null; then
        echo "Error: Window '$window_name' is no longer open" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate screen reference
    local output_num=""
    output_num=$(resolve_screen_reference "$screen_ref")
    if [[ -z "$output_num" ]]; then
        echo "Error: Invalid screen reference '$screen_ref'" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate position by checking against known positions
    local valid_position=false
    for pos_name in "${POSITION_MENU_ORDER[@]}"; do
        if [[ "${!pos_name}" == "$position" ]]; then
            valid_position=true
            break
        fi
    done

    if [[ "$valid_position" != true ]]; then
        echo "Error: Invalid position '$position'" >&3
        echo "Valid positions: Fullscreen, Right Half, Left Half, Top Half, Bottom Half," >&3
        echo "                Top Left, Top Right, Bottom Left, Bottom Right," >&3
        echo "                Left Third, Middle Third, Right Third" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Move window to screen and position
    move_window_to_screen "$uuid" "$screen_ref"
    move_window_to_position "$uuid" "$screen_ref" "$position"

    echo "Window '$window_name' moved to screen '$screen_ref' at '$position'" >&3
    debug_function_exit "$function_name"
    return 0
}
