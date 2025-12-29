#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh

check_and_set_guard "_KDOITALL_DESKTOP_LOADED" || return 0

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

    # Check if desktop number is within valid range (1 to NUM_DESKTOPS)
    if [[ "$desktop" -lt 1 || "$desktop" -gt "$NUM_DESKTOPS" ]]; then
        debug_error "$function_name" "$ERR_INVALID_DESKTOP_NUMBER" "'$desktop' (must be 1-$NUM_DESKTOPS)"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Pass Desktop number
    debug_log "$function_name" "Desktop Number Validation Passed"

    debug_function_exit "$function_name"
    echo "$desktop"
}

get_desktop_for_window_by_uuid() {
    local uuid="$1"
    local desktop=""
    local function_name="get_desktop_for_window_by_uuid"
    
    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

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

set_current_desktop() {
    local desktop="$1"
    local function_name="set_current_desktop"

    debug_function_enter "$function_name" "$@"

    # Validate Desktop number
    desktop=$(validate_desktop_number "$desktop")

    if [[ -z "$desktop" ]]; then
        debug_error "$function_name" "$ERR_DESKTOP_VALIDATION_FAILED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Set Current Desktop
    kdotool set_desktop "$desktop"
    sleep "$DESKTOP_DELAY"
    
    debug_log "$function_name" "Successfully switched to desktop $desktop"
    debug_function_exit "$function_name"

}

move_window_to_desktop_by_uuid() {
    local uuid="$1" 
    local desktop="$2"
    local function_name="move_window_to_desktop_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate Desktop number
    desktop=$(validate_desktop_number "$desktop")

    if [[ -z "$desktop" ]]; then
        debug_error "$function_name" "$ERR_DESKTOP_VALIDATION_FAILED" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    # Move Window to Desktop
    kdotool set_desktop_for_window "$uuid" "$desktop"
    sleep "$DESKTOP_DELAY"

    debug_log "$function_name" "Successfully moved '$uuid' to desktop $desktop"
    debug_function_exit "$function_name"
}

