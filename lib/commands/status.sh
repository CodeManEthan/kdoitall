#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_STATUS_COMMAND_LOADED" || return 0

# shellcheck source=../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

status_command() {
    local function_name="status_command"

    debug_function_enter "$function_name"

    echo "" >&3
    echo "kdoitall Status" >&3
    echo "═══════════════════════════════════════════════════════" >&3

    # Display active workspace windows
    display_status_active_workspaces

    # Display untracked windows
    display_status_untracked_windows

    debug_function_exit "$function_name"
    return 0
}
