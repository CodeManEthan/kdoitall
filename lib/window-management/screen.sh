#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error-codes.sh
# core/ydotool.sh
# core/ydotool.sh

check_and_set_guard "_KDOITALL_SCREEN_LOADED" || return 0

# shellcheck source=../core/screen-detection.sh
source "${LIB_DIR}/core/screen-detection.sh"

validate_screen_number() {
    local screen="$1"
    local function_name="validate_screen_number"

    debug_function_enter "$function_name" "$@"

    # Check if screen number was provided
    if [[ -z "$screen" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "No screen number provided"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Check if screen is a valid number
    if ! [[ "$screen" =~ ^[0-9]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Screen must be a number"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Check if screen detection has been run
    if [[ $DETECTED_SCREEN_COUNT -eq 0 ]]; then
        debug_error "$function_name" "$ERR_SCREEN_DETECTION_NOT_RUN" "Must call detect_screens() first"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    # Check if screen number is within valid range
    if [[ "$screen" -lt 1 || "$screen" -gt "$DETECTED_SCREEN_COUNT" ]]; then
        debug_error "$function_name" "$ERR_INVALID_SCREEN_NUMBER" "Screen: $screen (must be 1-$DETECTED_SCREEN_COUNT)"
        debug_function_exit "$function_name"
        echo ""
        return 1
    fi

    debug_log "$function_name" "Screen Number Validation Passed"
    debug_function_exit "$function_name"
    echo "$screen"
}

# Validate and resolve a screen reference (number, name, or alias)
# Returns: output number on success, empty on failure
validate_screen_reference() {
    local screen_ref="$1"
    local output_num=""
    local function_name="validate_screen_reference"
    
    debug_function_enter "$function_name" "$@"
    
    # Check if screen reference was provided
    if [[ -z "$screen_ref" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "No screen reference provided"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Resolve the screen reference to an output number
    output_num=$(resolve_screen_reference "$screen_ref")
    
    if [[ -z "$output_num" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_VALIDATION_FAILED" "Cannot resolve '$screen_ref'"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Screen reference '$screen_ref' resolved to output $output_num"
    debug_function_exit "$function_name"
    echo "$output_num"
}

# Calculate the absolute origin (top-left X,Y coordinates) of a screen
# Returns: "X,Y" on success, empty on failure
calculate_screen_origin() {
    local screen_ref="$1"
    local function_name="calculate_screen_origin"
    local output_num=""
    local screen_x=""
    local screen_y=""
    
    debug_function_enter "$function_name" "$@"
    
    # Resolve screen reference to output number
    output_num=$(resolve_screen_reference "$screen_ref")
    if [[ -z "$output_num" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_RESOLUTION_FAILED" "Cannot resolve '$screen_ref'"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get coordinates from detected info
    screen_x=$(get_screen_info "$output_num" "X")
    screen_y=$(get_screen_info "$output_num" "Y")
    
    if [[ -z "$screen_x" || -z "$screen_y" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_COORDINATES_NOT_FOUND" "Output $output_num"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Screen '$screen_ref' (Output $output_num) origin: ($screen_x, $screen_y)"
    debug_function_exit "$function_name"
    
    echo "${screen_x},${screen_y}"
}

# Move a window to a specific screen using absolute coordinates
# Supports output numbers, screen names, and aliases
move_window_to_screen_by_uuid() {
    local uuid="$1"
    local screen_ref="$2"
    local function_name="move_window_to_screen_by_uuid"
    local output_num=""
    local screen_origin=""
    local screen_x=""
    local screen_y=""

    debug_function_enter "$function_name" "$@"
    
    # Validate UUID parameter
    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Resolve screen reference (supports output numbers, names, aliases)
    output_num=$(resolve_screen_reference "$screen_ref")
    if [[ -z "$output_num" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_RESOLUTION_FAILED" "Cannot resolve '$screen_ref'"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get the absolute origin of the target screen
    screen_origin=$(calculate_screen_origin "$output_num")
    if [[ -z "$screen_origin" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_ORIGIN_CALCULATION_FAILED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Parse the origin coordinates
    screen_x="${screen_origin%,*}"
    screen_y="${screen_origin#*,}"
    
    debug_log "$function_name" "Moving window to screen '$screen_ref' (Output $output_num) at absolute ($screen_x, $screen_y)"
    
    # Move window to the screen's origin (top-left corner) using absolute coordinates
    move_window_by_uuid "$uuid" "$screen_x" "$screen_y"
    
    debug_log "$function_name" "Moved window '$uuid' to screen '$screen_ref'"
    debug_function_exit "$function_name"
}

move_window_to_position_by_uuid() {
    local uuid="$1"
    local screen_ref="$2"
    local position_mode="$3"
    local function_name="move_window_to_position_by_uuid"
    local output_num=""
    local screen_width=""
    local screen_height=""
    local screen_origin=""
    local screen_x=""
    local screen_y=""
    local x=""
    local y=""
    local width="" 
    local height=""

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Resolve screen reference (supports output numbers, names, aliases)
    output_num=$(resolve_screen_reference "$screen_ref")
    if [[ -z "$output_num" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_RESOLUTION_FAILED" "Cannot resolve '$screen_ref'"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get screen dimensions from detected info
    screen_width=$(get_screen_info "$output_num" "WIDTH")
    screen_height=$(get_screen_info "$output_num" "HEIGHT")
    
    if [[ -z "$screen_width" || -z "$screen_height" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_NOT_CONFIGURED" "Output $output_num"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Screen '$screen_ref' (Output $output_num) dimensions: ${screen_width}x${screen_height}"
    
    # Calculate the absolute origin (top-left corner) of this screen
    screen_origin=$(calculate_screen_origin "$output_num")
    if [[ -z "$screen_origin" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_ORIGIN_CALCULATION_FAILED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    screen_x="${screen_origin%,*}"
    screen_y="${screen_origin#*,}"
    
    debug_log "$function_name" "Screen '$screen_ref' (Output $output_num) absolute origin: ($screen_x, $screen_y)"
    
    # Calculate RELATIVE position and size within this screen based on mode    
    case "$position_mode" in
        "$FULLSCREEN")
            x=0
            y=0
            width="$screen_width"
            height="$screen_height"
            ;;
        "$LEFTHALF")
            x=0
            y=0
            width=$((screen_width / 2))
            height="$screen_height"
            ;;
        "$RIGHTHALF")
            x=$((screen_width / 2))
            y=0
            width=$((screen_width / 2))
            height="$screen_height"
            ;;
        "$TOPHALF")
            x=0
            y=0
            width="$screen_width"
            height=$((screen_height / 2))
            ;;
        "$BOTTOMHALF")
            x=0
            y=$((screen_height / 2))
            width="$screen_width"
            height=$((screen_height / 2))
            ;;
        "$TOPLEFT")
            x=0
            y=0
            width=$((screen_width / 2))
            height=$((screen_height / 2))
            ;;
        "$TOPRIGHT")
            x=$((screen_width / 2))
            y=0
            width=$((screen_width / 2))
            height=$((screen_height / 2))
            ;;
        "$BOTTOMLEFT")
            x=0
            y=$((screen_height / 2))
            width=$((screen_width / 2))
            height=$((screen_height / 2))
            ;;
        "$BOTTOMRIGHT")
            x=$((screen_width / 2))
            y=$((screen_height / 2))
            width=$((screen_width / 2))
            height=$((screen_height / 2))
            ;;
        "$LEFTTHIRD")
            x=0
            y=0
            width=$((screen_width / 3))
            height="$screen_height"
            ;;
        "$MIDDLETHIRD")
            x=$((screen_width / 3))
            y=0
            width=$((screen_width / 3))
            height="$screen_height"
            ;;
        "$RIGHTTHIRD")
            x=$((screen_width * 2 / 3))
            y=0
            width=$((screen_width / 3))
            height="$screen_height"
            ;;
        *)
            debug_error "$function_name" "$INVALID_POSITION_MODE" "Unknown mode: $position_mode"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # Convert RELATIVE coordinates to ABSOLUTE coordinates
    local absolute_x=$((screen_x + x))
    local absolute_y=$((screen_y + y))
    
    debug_log "$function_name" "$position_mode relative: x=$x y=$y"
    debug_log "$function_name" "$position_mode absolute: x=$absolute_x y=$absolute_y"
    debug_log "$function_name" "$position_mode size: width=$width height=$height"

    # Move and resize the window using ABSOLUTE coordinates
    move_window_by_uuid "$uuid" "$absolute_x" "$absolute_y"
    size_window_by_uuid "$uuid" "$width" "$height"

    debug_log "$function_name" "Moved window '$uuid' to $position_mode on screen '$screen_ref'"
    debug_function_exit "$function_name"
}