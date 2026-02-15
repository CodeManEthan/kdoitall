#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_CORE_LOADED" || return 0

# shellcheck source=../window-management/desktop.sh
source "${LIB_DIR}/window-management/desktop.sh"
# shellcheck source=../window-management/screen.sh
source "${LIB_DIR}/window-management/screen.sh"
# shellcheck source=../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"

execute_launch_window() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local launch_mode="$7"
    local launch_type="$8"
    local launch_command="$9"
    local class="${10}"
    local window_title_pattern="${11}"
    local launch_time="${12}"
    local function_name="execute_launch_window"
    local uuid=""
    local window_title=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$desktop" "desktop" || return 1
    validate_parameter_pass "$screen" "screen" || return 1
    validate_parameter_pass "$position" "position" || return 1
    validate_parameter_pass "$launch_mode" "launch_mode" || return 1
    validate_parameter_pass "$launch_type" "launch_type" || return 1
    validate_parameter_pass "$launch_command" "launch_command" || return 1

    debug_log "$function_name" "BEFORE DETECT WINDOWS: Class: '$class'"

    # Refresh database with current windows
    debug_log "$function_name" "Auto Detect Windows"
    auto_detect_windows

    debug_log "$function_name" "AFTER DETECT WINDOWS: Class: '$class'"

    # Check Window Exists (If SINGLE or UNIQUE Launch Mode)
    if [[ "$launch_mode" == "$LAUNCH_MODE_UNIQUE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE_OR_UNIQUE" ]]; then
        debug_log "$function_name" "Check Window Exists"
        uuid=$(get_uuid "$class" "$window_title_pattern")
    fi

    # Detect if Window exists
    if [[ -n "$uuid" && ( "$launch_mode" == "$LAUNCH_MODE_UNIQUE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE_OR_UNIQUE" ) ]]; then
        debug_log "$function_name" "Window already exists - $uuid."

        window_title=$(get_window_title "$uuid")

        raise_window "$uuid"

        # Claim Window in Database
        debug_log "$function_name" "Claim Window in app_windows table."
        db_claim_window "$workspace_name" "$window_name" "$uuid" "$window_title"
    else
        debug_log "$function_name" "Launch Window"

        # Launch Window
        eval "$launch_command"
        
        uuid=$(get_uuid_by_process_of_elimination_with_retry "$class" 5 0.1)

        # Detect and store app_class if not already stored
        if [[ -n "$app_id" && -z "$class" ]]; then
            class=$(detect_and_store_class "$uuid" "$app_id")
        fi

        window_title=$(get_window_title "$uuid")

        # Add Window to Database
        debug_log "$function_name" "Add Window to app_windows table."
        db_add_window "$workspace_name" "$window_name" "$uuid" "$class" "$window_title" 
    fi

    # Move Window to Desktop
    debug_log "$function_name" "Move Window to Desktop"
    move_window_to_desktop "$uuid" "$desktop"

    # Move Window to Screen
    debug_log "$function_name" "Move Window to Screen"
    move_window_to_screen "$uuid" "$screen"

    # Move Window to Position
    debug_log "$function_name" "Move Window to Position"
    move_window_to_position "$uuid" "$screen" "$position"

    debug_function_exit "$function_name"
}

execute_close_window() {
    local window_name="$1"
    local uuid=""
    local function_name="execute_close_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    uuid=$(db_get_uuid "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    close_window "$uuid"

    db_delete_window "$window_name"

    debug_function_exit "$function_name"
}

auto_detect_windows() {
    local function_name="auto_detect_windows"

    debug_function_enter "$function_name"
    
    debug_log "$function_name" "===== GET WINDOWS FROM KDOTOOL ====="
    get_existing_windows_uuid

    debug_log "$function_name" "===== GET CLASSES FROM KDOTOOL ====="
    get_existing_windows_class
    
    debug_log "$function_name" "===== GET TITLES FROM KDOTOOL ====="
    get_existing_windows_title

    debug_log "$function_name" "===== GET DATA FROM DATABASE ====="
    db_get_all_windows

    debug_log "$function_name" "===== KDOTOOL RESULTS ====="
    debug_array CURRENT_UUIDS
    debug_array CURRENT_CLASSES
    debug_array CURRENT_TITLES
    
    debug_log "$function_name" "===== DATABASE RESULTS ====="
    debug_array DB_UUIDS
    debug_array DB_CLASSES
    debug_array DB_TITLES

    debug_log "$function_name" "===== DELETE STALE WINDOWS ====="
    db_delete_stale_windows
    
    debug_log "$function_name" "===== ADD NEW WINDOWS ====="
    db_add_existing_windows

    debug_function_exit "$function_name"
}

launch_by_app_id() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local launch_mode=""
    local launch_type=""
    local class=""
    local window_title_pattern=""
    local launch_command=""
    local launch_time=""
    local function_name="launch_by_app_id"

    debug_function_enter "$function_name"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$desktop" "desktop" || return 1
    validate_parameter_pass "$screen" "screen" || return 1
    validate_parameter_pass "$position" "position" || return 1

    launch_type="$LAUNCH_TYPE_DESKTOP"

    debug_log "$function_name" "Obtain application properties from database."

    class=$(db_get_app_class "$app_id")
    window_title_pattern=$(db_get_window_title_pattern "$app_id")
    launch_mode=$(db_get_launch_mode "$app_id")
    launch_time=$(db_get_launch_time "$app_id")

    if [[ -z "$launch_mode" ]]; then
        launch_mode="$LAUNCH_MODE_UNKNOWN"
    fi

    launch_command="gtk-launch $app_id > /dev/null 2>&1 & disown"

     execute_launch_window \
     "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" \
     "$launch_mode" "$launch_type" "$launch_command" "$class" "$window_title_pattern" "$launch_time"

     debug_function_exit "$function_name"
}

detect_and_store_class() {
    local uuid="$1"
    local app_id="$2"
    local function_name="detect_and_store_class"
    
    debug_function_enter "$function_name" "$@"
    debug_log "$function_name" "Detecting app_class for $app_id..."
    
    # Detect actual window class from the launched window
    local detected_class=""
    detected_class=$(get_window_class "$uuid")
    
    if [[ -n "$detected_class" ]]; then
        # Store in database for future use
        if db_set_app_class "$app_id" "$detected_class"; then
            debug_log "$function_name" "✓ Auto-detected and stored app_class: $detected_class"
            debug_function_exit "$function_name"
            echo "$detected_class"
            return 0
        else
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to store app_class: $detected_class"
            debug_function_exit "$function_name"
            return 1
        fi
    else
        debug_error "$function_name" "$ERR_CLASS_DETECTION_FAILED" "Could not detect class for UUID $uuid"
        debug_function_exit "$function_name"
        return 1
    fi
}
