#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_MINIMIZE_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"

window_minimize() {
    local window_name="$1"
    local function_name="window_minimize"
    local uuid=""

    debug_function_enter "$function_name" "$@"

    if [[ -z "$window_name" ]]; then
        echo "Usage: kdoitall window minimize <window-name>" >&3
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

    minimize_window "$uuid"

    echo "Window '$window_name' minimized" >&3
    debug_function_exit "$function_name"
    return 0
}
