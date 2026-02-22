#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_LIST_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"

window_list() {
    local workspace_filter="${1:-}"
    local function_name="window_list"

    debug_function_enter "$function_name" "$@"

    # Sync database with live window state before displaying
    auto_detect_windows

    local result=""

    result=$(db_list_tracked_windows "$workspace_filter")

    if [[ -z "$result" ]]; then
        if [[ -n "$workspace_filter" ]]; then
            echo "No tracked windows found for workspace: $workspace_filter" >&3
        else
            echo "No tracked windows found" >&3
        fi
        debug_function_exit "$function_name"
        return 0
    fi

    # Print header — TITLE last so long titles have room to expand
    printf "%-30s %-20s %-20s %-8s %s\n" "WINDOW NAME" "WORKSPACE" "CLASS" "STATUS" "TITLE" >&3
    printf "%s\n" "$(printf '%.0s─' {1..120})" >&3

    # Print each window — all remaining entries are live after auto_detect_windows cleanup
    while IFS='|' read -r window_name workspace class title uuid; do
        printf "%-30s %-20s %-20s %-8s %s\n" "$window_name" "$workspace" "$class" "open" "$title" >&3
    done <<< "$result"

    debug_function_exit "$function_name"
    return 0
}
