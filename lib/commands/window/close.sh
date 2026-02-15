#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_CLOSE_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"

window_close() {
    local window_name="$1"
    local function_name="window_close"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$window_name" ]]; then
        echo "Usage: kdoitall window close <window-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # execute_close_window handles UUID lookup, close, and DB cleanup
    if ! execute_close_window "$window_name"; then
        echo "Error: Failed to close window '$window_name'" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    echo "Window '$window_name' closed" >&3
    debug_function_exit "$function_name"
    return 0
}
