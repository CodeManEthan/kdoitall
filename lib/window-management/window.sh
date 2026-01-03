#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh

check_and_set_guard "_KDOITALL_WINDOW_LOADED" || return 0

get_last_launched_uuid_by_class() {
    local class="$1"
    local uuid=""
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
    local uuid=""
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
    local uuid=""
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
        local found_class=""
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

get_uuid_by_process_of_elimination_with_retry() {
    local class="$1"
    local max_wait_seconds="${2:-5}"  # Default 5 seconds
    local retry_interval="${3:-0.1}"  # Default 100ms
    local function_name="get_uuid_by_process_of_elimination_with_retry"
    local uuid=""
    local elapsed=0
    local attempt=0
    
    debug_function_enter "$function_name" "$@"
    debug_log "$function_name" "Waiting up to ${max_wait_seconds}s for window (class: '$class')"
    
    while (( $(echo "$elapsed < $max_wait_seconds" | bc -l) )); do
        ((attempt++))
        
        # Attempt to get UUID
        uuid=$(get_uuid_by_process_of_elimination "$class")
        
        if [[ -n "$uuid" ]]; then
            debug_log "$function_name" "✓ Found UUID '$uuid' after ${elapsed}s (attempt #$attempt)"
            debug_function_exit "$function_name"
            echo "$uuid"
            return 0
        fi
        
        # Wait before next attempt
        sleep "$retry_interval"
        elapsed=$(echo "$elapsed + $retry_interval" | bc -l)
        
        debug_log "$function_name" "Attempt #$attempt: No UUID yet (elapsed: ${elapsed}s)"
    done
    
    # Timeout reached
    debug_error "$function_name" "$ERR_WINDOW_NOT_FOUND" "Timeout after ${max_wait_seconds}s waiting for window (class: '$class')"
    debug_function_exit "$function_name"
    return 1
}

get_window_title_by_uuid() {
    local uuid="$1" 
    local window_title=""
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
    local class=""
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

get_window_pid_by_uuid() {
    local uuid="$1" 
    local pid=""
    local function_name="get_window_pid_by_uuid"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_IS_REQUIRED"
        debug_function_exit "$function_name"
        return 1
    fi

    # Get window pid
    pid=$(kdotool getwindowpid "$uuid")

    if [[ -z "$pid" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_PID_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$pid'"

    debug_function_exit "$function_name"
    echo "$pid"
}

# ----------------------------------------------------------------------------
# get_process_name_by_pid()
# Get the process name from a PID
# Returns: Short process name (e.g., "firefox", "gimp-2.10") or empty if unavailable
# ----------------------------------------------------------------------------
get_process_name_by_pid() {
    local pid="$1"
    local process_name=""
    local function_name="get_process_name_by_pid"
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$pid" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get process name using ps
    process_name=$(ps -p "$pid" -o comm= 2>/dev/null)
    
    if [[ -z "$process_name" ]]; then
        debug_error "$function_name" "Process name not found for PID: $pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "PID '$pid' → '$process_name'"
    
    debug_function_exit "$function_name"
    echo "$process_name"
    return 0
}

# ----------------------------------------------------------------------------
# get_executable_path_by_pid()
# Get the full executable path from a PID
# Returns: Absolute path to executable (e.g., "/usr/lib/firefox/firefox") or empty
# ----------------------------------------------------------------------------
get_executable_path_by_pid() {
    local pid="$1"
    local executable_path=""
    local function_name="get_executable_path_by_pid"
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$pid" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get executable path from /proc
    executable_path=$(readlink -f /proc/"$pid"/exe 2>/dev/null)
    
    if [[ -z "$executable_path" ]]; then
        debug_error "$function_name" "Executable path not found for PID: $pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "PID '$pid' → '$executable_path'"
    
    debug_function_exit "$function_name"
    echo "$executable_path"
    return 0
}

get_window_size_by_uuid() {
    local uuid="$1" 
    local window_size=""
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
    local window_position=""
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
    local -a uuids=()
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
    local uuid=""
    local class=""
    local -a classes=()
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
    local uuid=""
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

    # Only verify class if provided
    if [[ -n "$class" ]]; then
        local found_class=""
        found_class=$(get_window_class_by_uuid "$uuid")

        if [[ "$class" != "$found_class" ]]; then
            debug_error "$function_name" "$ERR_WINDOW_CLASS_MISMATCH" "Expected class '$class', found '$found_class' for UUID '$uuid'"
            debug_function_exit "$function_name"
            return 0  # Return empty (no UUID) because class doesn't match
        fi

        debug_log "$function_name" "Class matches: '$class'"
    else
        debug_log "$function_name" "No class validation requested (class not provided)"
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
