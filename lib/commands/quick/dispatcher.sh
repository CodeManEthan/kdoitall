#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_QUICK_COMMAND_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../../db/window-tracking.sh
source "${LIB_DIR}/db/window-tracking.sh"
# shellcheck source=picker.sh
source "${LIB_DIR}/commands/quick/picker.sh"
# shellcheck source=actions.sh
source "${LIB_DIR}/commands/quick/actions.sh"
# shellcheck source=combo.sh
source "${LIB_DIR}/commands/quick/combo.sh"

# Global set by quick_show_picker to indicate selected window index
QUICK_SELECTED_INDEX=""

quick_command() {
    local function_name="quick_command"
    local action_result=""
    local sel_uuid=""
    local sel_display=""
    local sel_title=""
    local sel_location=""

    debug_function_enter "$function_name"

    # Sync DB with live window state
    auto_detect_windows

    # Main loop: picker → actions, with "go back" support
    while true; do
        QUICK_SELECTED_INDEX=""

        if ! quick_show_picker; then
            # User quit or no windows found
            debug_function_exit "$function_name"
            return 0
        fi

        sel_uuid="${QUICK_UUIDS[$QUICK_SELECTED_INDEX]}"
        sel_display="${QUICK_DISPLAY_NAMES[$QUICK_SELECTED_INDEX]}"
        sel_title="${QUICK_TITLES[$QUICK_SELECTED_INDEX]}"
        sel_location="${QUICK_LOCATIONS[$QUICK_SELECTED_INDEX]}"

        action_result=0
        quick_show_actions "$sel_uuid" "$sel_display" "$sel_title" "$sel_location" || action_result=$?

        if [[ "$action_result" -eq 2 ]]; then
            # "go back" — re-run picker
            continue
        fi

        # Action completed or user quit
        debug_function_exit "$function_name"
        return 0
    done
}
