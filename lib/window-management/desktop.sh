#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh
# utils/parsers.sh

validate_desktop_number() {
    local desktop="$1"
    local function_name+"validate_desktop_number"

    # Check if desktop number was provided
    if [[ -z "$desktop" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_MISSING_PARAMETER]} - No desktop number provided"
        echo ""
        return 1
    fi

    # Check if desktop is a valid number
    if ! [[ "$desktop" =~ ^[0-9]+$ ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_INVALID_PARAMETER]} - Desktop must be a number"
        echo ""
        return 1
    fi

    # Check if desktop number is within valid range (1 to NUM_DESKTOPS)
    if [[ "$desktop" -lt 1 || "$desktop" -gt "$NUM_DESKTOPS" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_INVALID_DESKTOP_NUMBER]} - '$desktop' (must be 1-$NUM_DESKTOPS)"
        echo ""
        return 1
    fi

    # Pass Desktop number
    echo "$desktop"
}

get_desktop_for_window() {
    local identifiers uuid window_name desktop
    local function_name="get_desktop_for_window"
    
    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Get Desktop for Window
    desktop=$(kdotool get_desktop_for_window "$uuid")
    
    if [[ -z "$desktop" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_DESKTOP_NOT_FOUND]}"
        return 1
    fi

    # Pass Desktop Number
    debug_log "$function_name: Window '$window_name' ($uuid) is on desktop $desktop" "verbose"
    echo "$desktop"
}

set_current_desktop() {
    local desktop="$1"
    local function_name="set_current_desktop"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Validate Desktop number
    desktop=$(validate_desktop_number "$desktop")

    if [[ -z "$desktop" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_DESKTOP_VALIDATION_FAILED]}"
        return 1
    fi

    # Set Current Desktop
    kdotool set_desktop "$desktop"
    sleep "$DESKTOP_DELAY"
    
    debug_log "$function_name: Successfully switched to desktop $desktop" "verbose"
}

move_window_to_desktop() {
    local desktop="$1"
    shift
    local identifiers uuid window_name
    local function_name="move_window_to_desktop"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Validate Desktop numbber
    desktop=$(validate_desktop_number "$desktop")

    if [[ -z "$desktop" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_DESKTOP_VALIDATION_FAILED]}"
        return 1
    fi

    # Move Window to Desktop
    kdotool set_desktop_for_window "$uuid" "$desktop"
    sleep "$DESKTOP_DELAY"

    debug_log "$function_name: Successfully moved window '$window_name' ($uuid) to desktop $desktop" "verbose"
}

