#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh
# utils/parsers.sh

get_last_launched_uuid_by_class() {
    local class="$1"
    local uuid
    local function_name="get_last_launched_uuid_by_class"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Get last UUID by class
    uuid=$(kdotool search --classname "$class" | tail -1)

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $class"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name: '$class' → '$uuid'" "verbose"
    echo "$uuid"
}

get_last_launched_uuid() {
    local uuid
    local function_name="get_last_launched_uuid"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Get last UUID
    uuid=$(kdotool search | tail -1)

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $class"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name: '$uuid'" "verbose"
    echo "$uuid"
}

get_window_title() {
    local identifiers uuid window_name window_title
    local function_name="get_window_title"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Get window title
    window_title=$(kdotool getwindowname "$uuid")

    if [[ -z "$window_title" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_WINDOW_TITLE_NOT_FOUND]} - '$window_name' ($uuid)"
        return 1
    fi

    debug_log "$function_name: '$window_name' ($uuid) → '$window_title'" "verbose"
    echo "$window_title"
}

get_window_class() {
    local identifiers uuid window_name class
    local function_name="get_window_class"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Get window class
    class=$(kdotool getwindowclassname "$uuid")

    if [[ -z "$class" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_WINDOW_CLASS_NOT_FOUND]} - '$window_name' ($uuid)"
        return 1
    fi

    debug_log "$function_name: '$window_name' ($uuid) → '$class'" "verbose"
    echo "$class"
}

get_window_size() {
    local identifiers uuid window_name window_size
    local function_name="get_window_size"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Get window size
    window_size=$(kdotool getwindowgeometry "$uuid" | grep "Geometry:" | awk '{print $2}')

    if [[ -z "$window_size" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_WINDOW_SIZE_NOT_FOUND]} - '$window_name' ($uuid)"
        return 1
    fi
    
    debug_log "$function_name: '$window_name' ($uuid) → '$window_size'" "verbose"
    echo "$window_size"
}

get_window_position() {
    local identifiers uuid window_name window_position
    local function_name="get_window_position"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Get window position
    window_position=$(kdotool getwindowgeometry "$uuid" | grep "Position:" | awk '{print $2}') || return 2
    
    if [[ -z "$window_position" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_WINDOW_POSITION_NOT_FOUND]} - '$window_name' ($uuid)"
        return 1
    fi

    debug_log "$function_name: '$window_name' ($uuid) → '$window_position'" "verbose"
    echo "$window_position"
}

get_existing_windows_uuid() {
    local uuids=()
    local function_name="get_existing_windows_uuid"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    mapfile -t uuids < <(kdotool search)

    debug_array uuids "verbose"
    printf '%s\n' "${uuids[@]}"
}

get_existing_windows_class_by_uuid() {
    local uuid
    local function_name="get_existing_windows_class_by_uuid"
    local classes=()

    debug_log "CALL FUNCTION: $function_name" "verbose"

    for uuid in "$@"; do  # Accept UUIDs as separate arguments
        class=$(kdotool getwindowclassname "$uuid")
        class="${class:-N/A}"
        classes+=("$class")
        printf '%s\n' "${class:-N/A}"
    done

    debug_array classes "verbose"
}

check_window_exists() {
    local window_title="$1"
    local class="$2"
    local uuid
    local function_name="check_window_exists"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Check current windows for matching Window Title & Class
    debug_log "$function_name: Search for $window_title" "verbose"
    uuid=$(kdotool search --name "$window_title" | head -1)

    if [[ -n "$uuid" ]]; then
        debug_log "$function_name: Found uuid $uuid for $window_title" "verbose"

        local found_class
        found_class=$(class_by_uuid "$uuid")

        if [[ "$class" == "$found_class" ]]; then
            debug_log "$function_name: Class is a match - Look: $class - Found: $found_class" "verbose"
            echo "$uuid"
            return 0
        else
            debug_log "Class does not match - Look: $class - Found: $found_class" "verbose"
        fi
    else
        debug_log "$function_name: UUID not found" "verbose"
        return 1
    fi

    return 1
}

activate_window() {
    local identifiers uuid window_name
    local function_name="activate_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Activate window
    kdotool windowactivate "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name: Window '$window_name' ($uuid) activated." "verbose"
}

raise_window() {
    local identifiers uuid window_name
    local function_name="raise_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Raise window
    kdotool windowraise "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name: Window '$window_name' ($uuid) raised." "verbose"
}

move_window() {
    local x="$1"
    local y="$2"
    shift 2

    local identifiers uuid window_name
    local function_name="move_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Move window
    kdotool windowmove "$uuid" "$x" "$y"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name: Window '$window_name' ($uuid) moved to x=$x y=$y." "verbose"
}

size_window() {
    local width="$1"
    local height="$2"
    shift 2

    local identifiers uuid window_name
    local function_name="size_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Size window
    kdotool windowsize "$uuid" "$width" "$height"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name: Window '$window_name' ($uuid) sized to width=$width height-$height." "verbose"
}

minimize_window() {
    local identifiers uuid window_name
    local function_name="minimize_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    #Minimize window
    kdotool windowminimize "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name: Window '$window_name' ($uuid) minimized." "verbose"
}

close_window() {
    local identifiers uuid window_name
    local function_name="close_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    # Close window
    kdotool windowclose "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name: Window '$window_name' ($uuid) closed." "verbose"
}

move_window_to_position() {
    local screen_num="$1"
    local position_mode="$2"
    shift 2
    
    local identifiers uuid window_name
    local function_name="move_window_to_position"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Parse UUID & Window Name
    identifiers=$(parse_window_identifiers "$@") || return 1
    IFS='|' read -r uuid window_name <<< "$identifiers"

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]}"
        return 1
    fi
    
    # Get screen size for the specified screen
    local screen_size_var="SCREEN${screen_num}_SIZE"
    local screen_size="${!screen_size_var}"
    
    if [[ -z "$screen_size" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_SCREEN_NOT_CONFIGURED]} - Screen: $screen_num"
        return 1
    fi

    debug_log "$function_name: Screen size for screen $screen_num is $screen_size" "verbose"
    
    # Parse screen dimensions
    local screen_width screen_height
    screen_width="${screen_size%x*}"
    screen_height="${screen_size#*x}"
    
    # Calculate position and size based on mode
    local x y width height
    
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
            debug_log "$function_name: ${ERROR_MESSAGES[$INVALID_POSITION_MODE]}"
            return 1
            ;;
    esac
    
    debug_log "$function_name: $position_mode Geometry: x=$x | y=$y | width=$width | height=$height" "verbose"

    # Move and resize the window
    move_window "$x" "$y" "$uuid"
    size_window "$width" "$height" "$uuid"

    debug_log "$function_name: Moved window '$window_name' ($uuid) to $position_mode position mode." "verbose"
}