#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SCREEN_LOADED" || return 0

# shellcheck source=../core/screen-detection.sh
source "${LIB_DIR}/core/screen-detection.sh"
# shellcheck source=window.sh
source "${LIB_DIR}/window-management/window.sh"

calculate_screen_origin() {
    local screen_ref="$1"
    local function_name="calculate_screen_origin"
    local output_num=""
    local screen_x=""
    local screen_y=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$screen_ref" "screen_ref" || return 1
    
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
}

validate_screen_reference() {
    local screen_ref="$1"
    local output_num=""
    local function_name="validate_screen_reference"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$screen_ref" "screen_ref" || return 1
    
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

move_window_to_screen() {
    local uuid="$1"
    local screen_ref="$2"
    local function_name="move_window_to_screen"
    local output_num=""
    local screen_origin=""
    local screen_x=""
    local screen_y=""

    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$screen_ref" "screen_ref" || return 1
    
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
    move_window "$uuid" "$screen_x" "$screen_y"
    
    debug_log "$function_name" "Moved window '$uuid' to screen '$screen_ref'"
    debug_function_exit "$function_name"
}

move_window_to_position() {
    local uuid="$1"
    local screen_ref="$2"
    local position_mode="$3"
    local function_name="move_window_to_position"
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

    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$screen_ref" "screen_ref" || return 1
    validate_parameter_pass "$position_mode" "position_mode" || return 1

    # If position_mode is a variable name (e.g. RIGHTHALF), expand to display value (e.g. "Right Half")
    if [[ "$position_mode" =~ ^[A-Z0-9_]+$ ]]; then
        local expanded="${!position_mode:-}"
        if [[ -n "$expanded" ]]; then
            position_mode="$expanded"
        fi
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
        "$LEFTTWOTHIRDS")
            x=0
            y=0
            width=$((screen_width * 2 / 3))
            height="$screen_height"
            ;;
        "$RIGHTTWOTHIRDS")
            x=$((screen_width / 3))
            y=0
            width=$((screen_width * 2 / 3))
            height="$screen_height"
            ;;
        "$LEFT60")
            x=0
            y=0
            width=$((screen_width * 60 / 100))
            height="$screen_height"
            ;;
        "$RIGHT40")
            x=$((screen_width * 60 / 100))
            y=0
            width=$((screen_width * 40 / 100))
            height="$screen_height"
            ;;
        "$LEFT40")
            x=0
            y=0
            width=$((screen_width * 40 / 100))
            height="$screen_height"
            ;;
        "$RIGHT60")
            x=$((screen_width * 40 / 100))
            y=0
            width=$((screen_width * 60 / 100))
            height="$screen_height"
            ;;
        "$CENTERHALF")
            x=$((screen_width / 4))
            y=0
            width=$((screen_width / 2))
            height="$screen_height"
            ;;
        "$LEFT25")
            x=0
            y=0
            width=$((screen_width / 4))
            height="$screen_height"
            ;;
        "$RIGHT25")
            x=$((screen_width * 3 / 4))
            y=0
            width=$((screen_width / 4))
            height="$screen_height"
            ;;
        "$CENTERTWOTHIRDS")
            x=$((screen_width / 6))
            y=0
            width=$((screen_width * 2 / 3))
            height="$screen_height"
            ;;
        "$TOPTWOTHIRDS")
            x=0
            y=0
            width="$screen_width"
            height=$((screen_height * 2 / 3))
            ;;
        "$BOTTOMTWOTHIRDS")
            x=0
            y=$((screen_height / 3))
            width="$screen_width"
            height=$((screen_height * 2 / 3))
            ;;
        "$TOP60")
            x=0
            y=0
            width="$screen_width"
            height=$((screen_height * 60 / 100))
            ;;
        "$BOTTOM40")
            x=0
            y=$((screen_height * 60 / 100))
            width="$screen_width"
            height=$((screen_height * 40 / 100))
            ;;
        "$TOP40")
            x=0
            y=0
            width="$screen_width"
            height=$((screen_height * 40 / 100))
            ;;
        "$BOTTOM60")
            x=0
            y=$((screen_height * 40 / 100))
            width="$screen_width"
            height=$((screen_height * 60 / 100))
            ;;
        *)
            debug_error "$function_name" "$ERR_INVALID_POSITION" "Unknown mode: $position_mode"
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
    move_window "$uuid" "$absolute_x" "$absolute_y"
    size_window "$uuid" "$width" "$height"

    debug_log "$function_name" "Moved window '$uuid' to $position_mode on screen '$screen_ref'"
    debug_function_exit "$function_name"
}

resolve_position() {
    local input="$1"
    local function_name="resolve_position"
    local input_lower=""
    local abbrev_var=""
    local pos_var=""
    local pos_value=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$input" "input" || return 1

    # Lowercase the input for case-insensitive matching
    input_lower="${input,,}"

    # Tier 1: Check against abbreviations
    if [[ -v POSITION_ABBREVIATIONS[$input_lower] ]]; then
        abbrev_var="${POSITION_ABBREVIATIONS[$input_lower]}"
        debug_log "$function_name" "Abbreviation match: '$input' → '$abbrev_var' → '${!abbrev_var}'"
        debug_function_exit "$function_name"
        echo "${!abbrev_var}"
        return 0
    fi

    # Tier 2: Check against full position names (case-insensitive)
    for pos_var in "${POSITION_MENU_ORDER[@]}"; do
        pos_value="${!pos_var}"
        if [[ "${pos_value,,}" == "$input_lower" ]]; then
            debug_log "$function_name" "Full name match: '$input' → '$pos_value'"
            debug_function_exit "$function_name"
            echo "$pos_value"
            return 0
        fi
    done

    # No match found
    debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Unknown position: '$input'"
    debug_function_exit "$function_name"
    return 1
}

detect_window_screen() {
    local uuid="$1"
    local function_name="detect_window_screen"
    local win_position=""
    local win_x=""
    local win_y=""
    local out=""
    local screen_x=""
    local screen_y=""
    local screen_width=""
    local screen_height=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get window position (returns "x,y")
    win_position=$(get_window_position "$uuid")
    if [[ -z "$win_position" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_POSITION_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    win_x="${win_position%,*}"
    win_y="${win_position#*,}"

    debug_log "$function_name" "Window position: ($win_x, $win_y)"

    # Check each enabled screen's bounding box
    for out in "${SCREEN_OUTPUT_IDS[@]}"; do
        if [[ "$(get_screen_info "$out" "ENABLED")" != "true" ]]; then
            continue
        fi

        screen_x=$(get_screen_info "$out" "X")
        screen_y=$(get_screen_info "$out" "Y")
        screen_width=$(get_screen_info "$out" "WIDTH")
        screen_height=$(get_screen_info "$out" "HEIGHT")

        if (( win_x >= screen_x && win_x < screen_x + screen_width &&
              win_y >= screen_y && win_y < screen_y + screen_height )); then
            debug_log "$function_name" "Window is on screen output $out"
            debug_function_exit "$function_name"
            echo "$out"
            return 0
        fi
    done

    debug_error "$function_name" "$ERR_SCREEN_NOT_FOUND" "No screen contains position ($win_x, $win_y)"
    debug_function_exit "$function_name"
    return 1
}

detect_window_position() {
    local uuid="$1"
    local output_num="$2"
    local function_name="detect_window_position"
    local win_position=""
    local win_x=""
    local win_y=""
    local win_size=""
    local win_width=""
    local win_height=""
    local screen_x=""
    local screen_y=""
    local screen_width=""
    local screen_height=""
    local rel_x=""
    local rel_y=""
    local pos_var=""
    local pos_value=""
    local expect_x=""
    local expect_y=""
    local expect_w=""
    local expect_h=""
    local tolerance=5

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$output_num" "output_num" || return 1

    # Get window position (returns "x,y")
    win_position=$(get_window_position "$uuid")
    if [[ -z "$win_position" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_POSITION_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    win_x="${win_position%,*}"
    win_y="${win_position#*,}"

    # Get window size (returns "widthxheight")
    win_size=$(get_window_size "$uuid")
    if [[ -z "$win_size" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_SIZE_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    win_width="${win_size%x*}"
    win_height="${win_size#*x}"

    # Get screen origin and dimensions
    screen_x=$(get_screen_info "$output_num" "X")
    screen_y=$(get_screen_info "$output_num" "Y")
    screen_width=$(get_screen_info "$output_num" "WIDTH")
    screen_height=$(get_screen_info "$output_num" "HEIGHT")

    # Calculate relative position within screen
    rel_x=$((win_x - screen_x))
    rel_y=$((win_y - screen_y))

    debug_log "$function_name" "Window relative: ($rel_x, $rel_y) size: ${win_width}x${win_height}"
    debug_log "$function_name" "Screen dimensions: ${screen_width}x${screen_height}"

    # Compare against each known position layout
    for pos_var in "${POSITION_MENU_ORDER[@]}"; do
        pos_value="${!pos_var}"

        # Calculate expected geometry for this position (same math as move_window_to_position)
        case "$pos_value" in
            "$FULLSCREEN")
                expect_x=0; expect_y=0
                expect_w="$screen_width"; expect_h="$screen_height"
                ;;
            "$LEFTHALF")
                expect_x=0; expect_y=0
                expect_w=$((screen_width / 2)); expect_h="$screen_height"
                ;;
            "$RIGHTHALF")
                expect_x=$((screen_width / 2)); expect_y=0
                expect_w=$((screen_width / 2)); expect_h="$screen_height"
                ;;
            "$TOPHALF")
                expect_x=0; expect_y=0
                expect_w="$screen_width"; expect_h=$((screen_height / 2))
                ;;
            "$BOTTOMHALF")
                expect_x=0; expect_y=$((screen_height / 2))
                expect_w="$screen_width"; expect_h=$((screen_height / 2))
                ;;
            "$TOPLEFT")
                expect_x=0; expect_y=0
                expect_w=$((screen_width / 2)); expect_h=$((screen_height / 2))
                ;;
            "$TOPRIGHT")
                expect_x=$((screen_width / 2)); expect_y=0
                expect_w=$((screen_width / 2)); expect_h=$((screen_height / 2))
                ;;
            "$BOTTOMLEFT")
                expect_x=0; expect_y=$((screen_height / 2))
                expect_w=$((screen_width / 2)); expect_h=$((screen_height / 2))
                ;;
            "$BOTTOMRIGHT")
                expect_x=$((screen_width / 2)); expect_y=$((screen_height / 2))
                expect_w=$((screen_width / 2)); expect_h=$((screen_height / 2))
                ;;
            "$LEFTTHIRD")
                expect_x=0; expect_y=0
                expect_w=$((screen_width / 3)); expect_h="$screen_height"
                ;;
            "$MIDDLETHIRD")
                expect_x=$((screen_width / 3)); expect_y=0
                expect_w=$((screen_width / 3)); expect_h="$screen_height"
                ;;
            "$RIGHTTHIRD")
                expect_x=$((screen_width * 2 / 3)); expect_y=0
                expect_w=$((screen_width / 3)); expect_h="$screen_height"
                ;;
            "$LEFTTWOTHIRDS")
                expect_x=0; expect_y=0
                expect_w=$((screen_width * 2 / 3)); expect_h="$screen_height"
                ;;
            "$RIGHTTWOTHIRDS")
                expect_x=$((screen_width / 3)); expect_y=0
                expect_w=$((screen_width * 2 / 3)); expect_h="$screen_height"
                ;;
            "$LEFT60")
                expect_x=0; expect_y=0
                expect_w=$((screen_width * 60 / 100)); expect_h="$screen_height"
                ;;
            "$RIGHT40")
                expect_x=$((screen_width * 60 / 100)); expect_y=0
                expect_w=$((screen_width * 40 / 100)); expect_h="$screen_height"
                ;;
            "$LEFT40")
                expect_x=0; expect_y=0
                expect_w=$((screen_width * 40 / 100)); expect_h="$screen_height"
                ;;
            "$RIGHT60")
                expect_x=$((screen_width * 40 / 100)); expect_y=0
                expect_w=$((screen_width * 60 / 100)); expect_h="$screen_height"
                ;;
            "$CENTERHALF")
                expect_x=$((screen_width / 4)); expect_y=0
                expect_w=$((screen_width / 2)); expect_h="$screen_height"
                ;;
            "$LEFT25")
                expect_x=0; expect_y=0
                expect_w=$((screen_width / 4)); expect_h="$screen_height"
                ;;
            "$RIGHT25")
                expect_x=$((screen_width * 3 / 4)); expect_y=0
                expect_w=$((screen_width / 4)); expect_h="$screen_height"
                ;;
            "$CENTERTWOTHIRDS")
                expect_x=$((screen_width / 6)); expect_y=0
                expect_w=$((screen_width * 2 / 3)); expect_h="$screen_height"
                ;;
            "$TOPTWOTHIRDS")
                expect_x=0; expect_y=0
                expect_w="$screen_width"; expect_h=$((screen_height * 2 / 3))
                ;;
            "$BOTTOMTWOTHIRDS")
                expect_x=0; expect_y=$((screen_height / 3))
                expect_w="$screen_width"; expect_h=$((screen_height * 2 / 3))
                ;;
            "$TOP60")
                expect_x=0; expect_y=0
                expect_w="$screen_width"; expect_h=$((screen_height * 60 / 100))
                ;;
            "$BOTTOM40")
                expect_x=0; expect_y=$((screen_height * 60 / 100))
                expect_w="$screen_width"; expect_h=$((screen_height * 40 / 100))
                ;;
            "$TOP40")
                expect_x=0; expect_y=0
                expect_w="$screen_width"; expect_h=$((screen_height * 40 / 100))
                ;;
            "$BOTTOM60")
                expect_x=0; expect_y=$((screen_height * 40 / 100))
                expect_w="$screen_width"; expect_h=$((screen_height * 60 / 100))
                ;;
            *)
                continue
                ;;
        esac

        # Check if actual geometry matches expected within tolerance
        if (( rel_x >= expect_x - tolerance && rel_x <= expect_x + tolerance &&
              rel_y >= expect_y - tolerance && rel_y <= expect_y + tolerance &&
              win_width >= expect_w - tolerance && win_width <= expect_w + tolerance &&
              win_height >= expect_h - tolerance && win_height <= expect_h + tolerance )); then
            debug_log "$function_name" "Position detected: '$pos_value'"
            debug_function_exit "$function_name"
            echo "$pos_value"
            return 0
        fi
    done

    # No known position matched — window has custom/manual geometry
    debug_log "$function_name" "No known position matched for window geometry"
    debug_function_exit "$function_name"
    echo ""
    return 0
}
