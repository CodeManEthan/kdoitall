#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_STATUS_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"

window_status() {
    local window_name="$1"
    local function_name="window_status"
    local uuid=""

    debug_function_enter "$function_name" "$@"

    if [[ -z "$window_name" ]]; then
        echo "Usage: kdoitall window status <window-name>" >&3
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

    # Get stored data from database
    local workspace_name=""
    local class=""
    local stored_title=""

    workspace_name=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        "SELECT workspace_name FROM app_windows WHERE window_name = :window_name;" 2>/dev/null)
    class=$(db_get_class "$window_name")
    stored_title=$(db_get_window_title "$window_name")

    # Check if window is still alive
    if ! kdotool getwindowname "$uuid" &>/dev/null; then
        echo "Window: $window_name" >&3
        echo "  Workspace:    $workspace_name" >&3
        echo "  UUID:         $uuid" >&3
        echo "  Class:        $class" >&3
        echo "  Title:        $stored_title" >&3
        echo "  Status:       closed" >&3
        debug_function_exit "$function_name"
        return 0
    fi

    # Query live data from kdotool
    local live_title=""
    local position=""
    local size=""
    local desktop=""
    local pid=""

    live_title=$(get_window_title "$uuid" 2>/dev/null) || live_title="N/A"
    position=$(get_window_position "$uuid" 2>/dev/null) || position="N/A"
    size=$(get_window_size "$uuid" 2>/dev/null) || size="N/A"
    desktop=$(get_desktop_for_window "$uuid" 2>/dev/null) || desktop="N/A"
    pid=$(get_window_pid "$uuid" 2>/dev/null) || pid="N/A"

    echo "Window: $window_name" >&3
    echo "  Workspace:    $workspace_name" >&3
    echo "  UUID:         $uuid" >&3
    echo "  Class:        $class" >&3
    echo "  Title:        $live_title" >&3
    echo "  Desktop:      $desktop" >&3
    echo "  Position:     $position" >&3
    echo "  Size:         $size" >&3
    echo "  PID:          $pid" >&3
    echo "  Status:       open" >&3

    debug_function_exit "$function_name"
    return 0
}
