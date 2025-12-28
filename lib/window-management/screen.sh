#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh
# core/ydotool.sh

validate_screen_number() {
    local screen="$1"
    local function_name+"validate_screen_number"

    # Check if screen number was provided
    if [[ -z "$screen" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_MISSING_PARAMETER]} - No screen number provided"
        echo ""
        return 1
    fi

    # Check if screen is a valid number
    if ! [[ "$screen" =~ ^[0-9]+$ ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_INVALID_PARAMETER]} - Screen must be a number"
        echo ""
        return 1
    fi

    # Check if screen number is within valid range (1 to NUM_SCREENS)
    if [[ "$screen" -lt 1 || "$screen" -gt "$NUM_SCREENS" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_INVALID_SCREEN_NUMBER]} - '$screen' (must be 1-$NUM_SCREENS)"
        echo ""
        return 1
    fi

    echo "$screen"
}

# Move focus to a specific screen (simulates the keyboard shortcut)
set_current_screen() {
    local screen_num="$1"
    local function_name="set_current_screen"
    
    # Validate Screen number
    screen_num=$(validate_screen_number "$screen_num")

    if [[ -z "$screen_num" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_VALIDATION_FAILED]}"
        return 1
    fi
    
    # Get the key for this screen
    local screen_key_var="SCREEN${screen_num}_KEY"
    local screen_key="${!screen_key_var}"
    
    if [[ -z "$screen_key" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_KEY_NOT_CONFIGURED]}"
        return 1
    fi
    
    # Parse the modifier string (e.g., "super + ctrl" -> ["super", "ctrl"])
    IFS=' + ' read -ra modifiers <<< "$MOVE_TO_SCREEN_MODIFIER"

    if [[ -z "${modifiers[0]}" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_MODIFIER_KEY_NOT_CONFIGURED]}"
        return 1
    fi
    
    # Build the chord array with modifiers + screen key
    local chord_keys=("${modifiers[@]}" "$screen_key")
    
    debug_log "$function_name: Moving to screen $screen_num with shortcut: ${chord_keys[*]}" "verbose"
    chord "${chord_keys[@]}"
}

# Move the active window to a specific screen (simulates the keyboard shortcut)
move_active_window_to_screen() {
    local screen_num="$1"
    local function_name="move_active_window_to_screen"
    
    # Validate Screen number
    screen_num=$(validate_screen_number "$screen_num")

    if [[ -z "$screen_num" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_VALIDATION_FAILED]}"
        return 1
    fi
    
    # Get the key for this screen
    local screen_key_var="SCREEN${screen_num}_KEY"
    local screen_key="${!screen_key_var}"
    
    if [[ -z "$screen_key" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_KEY_NOT_CONFIGURED]}"
        return 1
    fi
    
    # Parse the modifier string (e.g., "super + ctrl + shift" -> ["super", "ctrl", "shift"])
    IFS=' + ' read -ra modifiers <<< "$MOVE_WINDOW_TO_SCREEN_MODIFIER"
    
    if [[ -z "${modifiers[0]}" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_MODIFIER_KEY_NOT_CONFIGURED]}"
        return 1
    fi

    # Build the chord array with modifiers + screen key
    local chord_keys=("${modifiers[@]}" "$screen_key")
    
    debug_log "$function_name: Moving window to screen $screen_num with shortcut: ${chord_keys[*]}" "verbose"
    chord "${chord_keys[@]}"
}