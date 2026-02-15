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

    local query=""
    local result=""

    if [[ -n "$workspace_filter" ]]; then
        result=$(sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :workspace '$workspace_filter'" \
            ".mode tabs
             SELECT window_name, workspace_name, class, COALESCE(window_title, 'N/A'), uuid
             FROM app_windows
             WHERE workspace_name = :workspace
             ORDER BY window_name;" 2>/dev/null)
    else
        result=$(sqlite3 "$KDOITALL_DB" \
            ".mode tabs
             SELECT window_name, workspace_name, class, COALESCE(window_title, 'N/A'), uuid
             FROM app_windows
             ORDER BY workspace_name, window_name;" 2>/dev/null)
    fi

    if [[ -z "$result" ]]; then
        if [[ -n "$workspace_filter" ]]; then
            echo "No tracked windows found for workspace: $workspace_filter" >&3
        else
            echo "No tracked windows found" >&3
        fi
        debug_function_exit "$function_name"
        return 0
    fi

    # Print header
    printf "%-30s %-20s %-20s %-30s %s\n" "WINDOW NAME" "WORKSPACE" "CLASS" "TITLE" "STATUS" >&3
    printf "%s\n" "$(printf '%.0s─' {1..120})" >&3

    # Print each window with live status check
    while IFS=$'\t' read -r window_name workspace class title uuid; do
        local status="unknown"
        # Check if window is still alive via kdotool
        if kdotool getwindowname "$uuid" &>/dev/null; then
            status="open"
        else
            status="closed"
        fi
        printf "%-30s %-20s %-20s %-30s %s\n" "$window_name" "$workspace" "$class" "$title" "$status" >&3
    done <<< "$result"

    debug_function_exit "$function_name"
    return 0
}
