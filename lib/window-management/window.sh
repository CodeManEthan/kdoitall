#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh

get_last_launched_uuid_by_class() {
    local class="$1"
    local uuid
    local function_name="get_last_launched_uuid_by_class"

    debug_function_enter "$function_name" "$@"

    # Get last UUID by class
    uuid=$(kdotool search --classname "$class" | tail -1)

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$class"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$class' → '$uuid'"
    
    debug_function_exit "$function_name"
    echo "$uuid"
}

get_last_launched_uuid() {
    local uuid
    local function_name="get_last_launched_uuid"

    debug_function_enter "$function_name"

    # Get last UUID
    uuid=$(kdotool search | tail -1)

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$uuid'"

    debug_function_exit "$function_name"
    echo "$uuid"
}

get_uuid_by_window_title() {
    local window_title="$1"
    local uuid
    local function_name="get_uuid_by_window_title"

    debug_function_enter "$function_name" "$@"

    uuid=$(kdotool search --name "$window_title")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$window_title' → '$uuid'"

    debug_function_exit "$function_name"
    echo "$uuid"    
}

get_uuid_by_process_of_elimination() {
    local class="$1"  # Optional class parameter for validation
    local -a current_uuids=()
    local -a db_uuids=()
    local new_uuid=""
    local found_count=0
    local function_name="get_uuid_by_process_of_elimination"

    debug_function_enter "$function_name" "$@"

    # Get all current window UUIDs from kdotool
    mapfile -t current_uuids < <(get_existing_windows_uuid)
    
    # Get all UUIDs from database
    mapfile -t db_uuids < <(sqlite3 "$KDOITALL_DB" "SELECT uuid FROM app_windows WHERE uuid IS NOT NULL")
    
    debug_log "$function_name" "Current windows: ${#current_uuids[@]}, Database windows: ${#db_uuids[@]}"
    
    # Build lookup table of database UUIDs
    declare -A db_lookup
    for uuid in "${db_uuids[@]}"; do
        db_lookup["$uuid"]=1
    done
    
    # Find UUIDs that exist in current windows but not in database
    for uuid in "${current_uuids[@]}"; do
        if [[ ! -v db_lookup[$uuid] ]]; then
            new_uuid="$uuid"
            ((found_count++))
            debug_log "$function_name" "Found new UUID: $uuid"
        fi
    done
    
    if [[ $found_count -eq 0 ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "No new windows found"
        debug_function_exit "$function_name"
        return 1
    elif [[ $found_count -gt 1 ]]; then
        debug_error "$function_name" "$ERR_MULTIPLE_WINDOWS_FOUND" "Found $found_count new windows, expected 1"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate class if provided
    if [[ -n "$class" ]]; then
        local found_class
        found_class=$(get_window_class_by_uuid "$new_uuid")
        
        if [[ "$class" != "$found_class" ]]; then
            debug_error "$function_name" "$ERR_WINDOW_CLASS_MISMATCH" "Expected class '$class', found '$found_class' for UUID '$new_uuid'"
            debug_function_exit "$function_name"
            return 1
        fi
        
        debug_log "$function_name" "Class validation passed: '$class' matches for UUID '$new_uuid'"
    fi
    
    debug_log "$function_name" "New window UUID: $new_uuid"
    debug_function_exit "$function_name"
    echo "$new_uuid"
}

get_window_title_by_uuid() {
    local uuid="$1" 
    local window_title
    local function_name="get_window_title_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Get window title
    window_title=$(kdotool getwindowname "$uuid")

    if [[ -z "$window_title" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_TITLE_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$window_title'"

    debug_function_exit "$function_name"
    echo "$window_title"
}

get_window_class_by_uuid() {
    local uuid="$1" 
    local class
    local function_name="get_window_class_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Get window class
    class=$(kdotool getwindowclassname "$uuid")

    if [[ -z "$class" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_CLASS_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$class'"

    debug_function_exit "$function_name"
    echo "$class"
}

get_window_size_by_uuid() {
    local uuid="$1" 
    local window_size
    local function_name="get_window_size_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Get window size
    window_size=$(kdotool getwindowgeometry "$uuid" | grep "Geometry:" | awk '{print $2}')

    if [[ -z "$window_size" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_SIZE_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "'$uuid' → '$window_size'"

    debug_function_exit "$function_name"
    echo "$window_size"
}

get_window_position_by_uuid() {
    local uuid="$1" 
    local window_position
    local function_name="get_window_position_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Get window position
    window_position=$(kdotool getwindowgeometry "$uuid" | grep "Position:" | awk '{print $2}')
    
    if [[ -z "$window_position" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_POSITION_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$window_position'"

    debug_function_exit "$function_name"
    echo "$window_position"
}

get_existing_windows_uuid() {
    local uuids=()
    local function_name="get_existing_windows_uuid"

    debug_function_enter "$function_name"

    mapfile -t uuids < <(kdotool search)

    if [[ ${#uuids[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0  # Not an error - just no windows open
    fi

    debug_array uuids

    debug_function_exit "$function_name"
    printf '%s\n' "${uuids[@]}"
}

get_existing_windows_class_by_uuids() {
    local uuid
    local classes=()
    local function_name="get_existing_windows_class_by_uuids"

    debug_function_enter "$function_name" "$@"

    for uuid in "$@"; do  # Accept UUIDs as separate arguments
        class=$(kdotool getwindowclassname "$uuid")
        class="${class:-N/A}"
        classes+=("$class")
        printf '%s\n' "${class:-N/A}"
    done

    debug_array classes
    debug_function_exit "$function_name"
}

check_window_exists_by_window_title_and_class() {
    local window_title="$1"
    local class="$2"
    local uuid
    local function_name="check_window_exists_by_window_title_and_class"

    debug_function_enter "$function_name" "$@"

    # Search for window by title
    uuid=$(kdotool search --name "$window_title" | head -1)

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name" "No window found with title '$window_title'"
        debug_function_exit "$function_name"
        return 0
    fi

    debug_log "$function_name" "Found window '$uuid' with title '$window_title'"

    # Verify class matches
    local found_class
    found_class=$(get_window_class_by_uuid "$uuid")

    if [[ "$class" != "$found_class" ]]; then
        debug_log "$function_name" "Class mismatch: expected '$class', found '$found_class'"
        debug_function_exit "$function_name"
        return 0
    fi

    debug_log "$function_name" "Class matches: '$class'"
    
    debug_function_exit "$function_name"
    echo "$uuid"
    return 0
}

activate_window_by_uuid() {
    local uuid="$1"
    local function_name="activate_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Activate window
    kdotool windowactivate "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' activated."
    debug_function_exit "$function_name"
}

raise_window_by_uuid() {
    local uuid="$1"
    local function_name="raise_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Raise window
    kdotool windowraise "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' raised."
    debug_function_exit "$function_name"
}

move_window_by_uuid() {
    local uuid="$1"
    local x="$2"
    local y="$3"
    local function_name="move_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Move window
    kdotool windowmove "$uuid" "$x" "$y"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' moved to x=$x y=$y."
    debug_function_exit "$function_name"
}

size_window_by_uuid() {
    local uuid="$1"
    local width="$2"
    local height="$3"
    local function_name="size_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Size window
    kdotool windowsize "$uuid" "$width" "$height"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' sized to width=$width height=$height."
    debug_function_exit "$function_name"
}

minimize_window_by_uuid() {
    local uuid="$1"
    local function_name="minimize_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    #Minimize window
    kdotool windowminimize "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' minimized."
    debug_function_exit "$function_name"
}

close_window_by_uuid() {
    local uuid="$1"
    local function_name="close_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Close window
    kdotool windowclose "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' closed."
    debug_function_exit "$function_name"
}

move_window_to_position_by_uuid() {
    local uuid="$1"
    local screen_num="$2"
    local position_mode="$3"
    local function_name="move_window_to_position_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get screen size for the specified screen
    local screen_size_var="SCREEN${screen_num}_SIZE"
    local screen_size="${!screen_size_var}"
    
    if [[ -z "$screen_size" ]]; then
        debug_error "$function_name" "$ERR_SCREEN_NOT_CONFIGURED" "Screen: $screen_num"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Screen size for screen $screen_num is $screen_size"
    
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
            debug_error "$function_name" "$INVALID_POSITION_MODE"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    debug_log "$function_name" "$position_mode Geometry: x=$x | y=$y | width=$width | height=$height"

    # Move and resize the window
    move_window_by_uuid "$uuid" "$x" "$y"
    size_window_by_uuid "$uuid" "$width" "$height"

    debug_log "$function_name" "Moved window '$uuid' to $position_mode position mode."
    debug_function_exit "$function_name"
}