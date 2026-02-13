#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DESKTOP_LOADED" || return 0

get_desktop_for_window() {
    local uuid="$1"
    local desktop=""
    local function_name="get_desktop_for_window"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get Desktop for Window
    desktop=$(kdotool get_desktop_for_window "$uuid")
    
    if [[ -z "$desktop" ]]; then
        debug_error "$function_name" "$ERR_DESKTOP_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass Desktop Number
    debug_log "$function_name" "'$uuid' is on desktop $desktop"

    debug_function_exit "$function_name"
    echo "$desktop"
}

get_current_desktop() {
    local desktop=""
    local function_name="get_desktop_for_window"
    
    debug_function_enter "$function_name"

    # Get Desktop for Window
    desktop=$(kdotool get_desktop)
    
    if [[ -z "$desktop" ]]; then
        debug_error "$function_name" "$ERR_DESKTOP_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass Desktop Number
    debug_log "$function_name" "Current desktop is $desktop"

    debug_function_exit "$function_name"
    echo "$desktop"
}

validate_desktop_number() {
    local desktop="$1"
    local function_name="validate_desktop_number"

    debug_function_enter "$function_name" "$@"

    # Check if desktop number was provided
    if [[ -z "$desktop" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "No desktop number provided"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Check if desktop is a valid number
    if ! [[ "$desktop" =~ ^[0-9]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Desktop must be a number"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Check if desktop detection has been run
    if [[ $DETECTED_DESKTOP_COUNT -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DESKTOP_DETECTION_NOT_RUN" "Must call detect_desktops() first"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Check if desktop number is within valid range
    if [[ "$desktop" -lt 1 || "$desktop" -gt "$DETECTED_DESKTOP_COUNT" ]]; then
        debug_error "$function_name" "$ERR_INVALID_DESKTOP_NUMBER" "'$desktop' (must be 1-$DETECTED_DESKTOP_COUNT)"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Pass Desktop number
    debug_log "$function_name" "Desktop Number Validation Passed"

    debug_function_exit "$function_name"
}

set_current_desktop() {
    local desktop="$1"
    local function_name="set_current_desktop"

    debug_function_enter "$function_name" "$@"

    validate_desktop_number "$desktop" || return 1

    # Set Current Desktop
    kdotool set_desktop "$desktop"
    sleep "$DESKTOP_DELAY"
    
    debug_log "$function_name" "Successfully switched to desktop $desktop"
    debug_function_exit "$function_name"

}

move_window_to_desktop() {
    local uuid="$1" 
    local desktop="$2"
    local function_name="move_window_to_desktop"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$desktop" "desktop" || return 1
    validate_desktop_number "$desktop" || return 1

    # Move Window to Desktop
    kdotool set_desktop_for_window "$uuid" "$desktop"
    sleep "$DESKTOP_DELAY"

    debug_log "$function_name" "Successfully moved '$uuid' to desktop $desktop"
    debug_function_exit "$function_name"
}

