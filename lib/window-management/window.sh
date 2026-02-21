#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_LOADED" || return 0

# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"

CURRENT_UUIDS=()
CURRENT_CLASSES=()
CURRENT_TITLES=()

refresh_current_windows() {
    local function_name="refresh_current_windows"

    debug_function_enter "$function_name"

    # Reset all global arrays
    CURRENT_UUIDS=()
    CURRENT_CLASSES=()
    CURRENT_TITLES=()

    # Get all window UUIDs
    local -a uuids=()
    mapfile -t uuids < <(kdotool search)

    if [[ ${#uuids[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0
    fi

    # Collect UUID, class, and title per window in a single pass.
    # This ensures the three arrays stay aligned even if a window
    # disappears mid-scan — the failed property gets "N/A" and the
    # arrays never drift out of sync.
    local uuid=""
    local class=""
    local title=""
    for uuid in "${uuids[@]}"; do
        class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
        class="${class:-N/A}"

        title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""
        title="${title:-N/A}"

        CURRENT_UUIDS+=("$uuid")
        CURRENT_CLASSES+=("$class")
        CURRENT_TITLES+=("$title")
    done

    debug_log "$function_name" "Retrieved ${#CURRENT_UUIDS[@]} windows (UUIDs, classes, titles)"
    debug_function_exit "$function_name"
    return 0
}

get_uuid_by_process_of_elimination() {
    local class="$1"  # Optional class parameter for validation
    local is_retry="${2:-FALSE}"
    local uuid=""
    local new_uuid=""
    local found_count=0
    local function_name="get_uuid_by_process_of_elimination"

    debug_function_enter "$function_name" "$@"

    # Get all current window UUIDs from kdotool (populates CURRENT_UUIDS)
    get_existing_windows_uuid
    
    # Get all UUIDs from database (populates DB_UUIDS)
    db_get_existing_window_uuids
    
    debug_log "$function_name" "Current windows: ${#CURRENT_UUIDS[@]}, Database windows: ${#DB_UUIDS[@]}"
    
    # Build lookup table of database UUIDs
    local -A db_lookup
    for uuid in "${DB_UUIDS[@]}"; do
        db_lookup["$uuid"]=1
    done
    
    # Find UUIDs that exist in current windows but not in database
    for uuid in "${CURRENT_UUIDS[@]}"; do
        if [[ ! -v db_lookup[$uuid] ]]; then
            new_uuid="$uuid"
            ((found_count++))
            debug_log "$function_name" "Found new UUID: $uuid"
        fi
    done
    
    if [[ $found_count -eq 0 ]]; then
        if [[ "$is_retry" == "FALSE" ]]; then
            debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "No new windows found"
            debug_function_exit "$function_name"
            return 0
        fi
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
        found_class=$(get_window_class "$new_uuid")
        
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
        
        # Attempt to get UUID (class validation happens inside this function)
        uuid=$(get_uuid_by_process_of_elimination "$class" "TRUE")
        
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

get_existing_windows_uuid() {
    local function_name="get_existing_windows_uuid"

    debug_function_enter "$function_name"

    CURRENT_UUIDS=()

    mapfile -t CURRENT_UUIDS < <(kdotool search)

    if [[ ${#CURRENT_UUIDS[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0  # Not an error - just no windows open
    fi

    debug_log "$function_name" "Retrieved ${#CURRENT_UUIDS[@]} uuids"
    debug_function_exit "$function_name"
    return 0
}

get_uuid() {
    local class="$1"
    local window_title="$2"
    local -a matching_uuids=()
    local uuid=""
    local function_name="get_uuid"

    debug_function_enter "$function_name" "$@"

    # Need at least one search criterion
    if [[ -z "$class" && -z "$window_title" ]]; then
        debug_error "$function_name" "$ERR_INVALID_ARGUMENT" "Must provide at least class or window_title"
        debug_function_exit "$function_name"
        return 1
    fi

    # Step 1: Search by class if provided
    if [[ -n "$class" ]]; then
        debug_log "$function_name" "Searching for windows with class: '$class'"
        mapfile -t matching_uuids < <(kdotool search --class "$class")

        if [[ ${#matching_uuids[@]} -eq 0 ]]; then
            debug_log "$function_name" "No windows found with class '$class'"
            debug_function_exit "$function_name"
            return 0
        fi

        debug_log "$function_name" "Found ${#matching_uuids[@]} window(s) with class '$class'"
    else
        # No class filter - get all windows
        debug_log "$function_name" "No class filter, searching all windows"
        mapfile -t matching_uuids < <(kdotool search)
    fi

    # Step 2: Filter by window title if provided
    if [[ -n "$window_title" ]]; then
        debug_log "$function_name" "Filtering ${#matching_uuids[@]} windows by title: '$window_title'"
        
        local -a title_matches=()
        local current_title=""
        
        for uuid in "${matching_uuids[@]}"; do
            current_title=$(kdotool getwindowname "$uuid")
            if [[ "$current_title" == "$window_title" ]]; then
                title_matches+=("$uuid")
                debug_log "$function_name" "Title match: UUID '$uuid' has title '$current_title'"
            fi
        done
        
        matching_uuids=("${title_matches[@]}")
        
        if [[ ${#matching_uuids[@]} -eq 0 ]]; then
            debug_log "$function_name" "No windows found matching title '$window_title'"
            debug_function_exit "$function_name"
            return 0
        fi
        
        debug_log "$function_name" "Found ${#matching_uuids[@]} window(s) matching filters"
    fi

    # Step 3: Return result based on match count
    if [[ ${#matching_uuids[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0
    elif [[ ${#matching_uuids[@]} -eq 1 ]]; then
        uuid="${matching_uuids[0]}"
        debug_log "$function_name" "Found exactly one UUID: '$uuid'"
        debug_function_exit "$function_name"
        echo "$uuid"
        return 0
    else
        debug_error "$function_name" "$ERR_MULTIPLE_WINDOWS_FOUND" "Found ${#matching_uuids[@]} windows"
        debug_function_exit "$function_name"
        return 1
    fi
}

get_window_class() {
    local uuid="$1" 
    local class=""
    local function_name="get_window_class"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

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

get_window_title() {
    local uuid="$1" 
    local window_title=""
    local function_name="get_window_title"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

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

get_window_pid() {
    local uuid="$1" 
    local pid=""
    local function_name="get_window_pid"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

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

get_process_name() {
    local pid="$1"
    local process_name=""
    local function_name="get_process_name"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$pid" "pid" || return 1
    
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

get_executable_path() {
    local pid="$1"
    local executable_path=""
    local function_name="get_executable_path"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$pid" "pid" || return 1
    
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

get_window_size() {
    local uuid="$1" 
    local window_size=""
    local function_name="get_window_size"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

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

get_window_position() {
    local uuid="$1" 
    local window_position=""
    local function_name="get_window_position"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

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

get_active_window_uuid() {
    local uuid=""
    local function_name="get_active_window_uuid"

    debug_function_enter "$function_name"

    # Get the currently focused window UUID
    uuid=$(kdotool getactivewindow 2>/dev/null)

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name" "No active window (desktop may be focused)"
        debug_function_exit "$function_name"
        return 0
    fi

    debug_log "$function_name" "Active window: '$uuid'"
    debug_function_exit "$function_name"
    echo "$uuid"
}

window_exists() {
    local uuid="$1"
    local function_name="window_exists"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Check if UUID exists in CURRENT_UUIDS global array
    for current_uuid in "${CURRENT_UUIDS[@]}"; do
        if [[ "$current_uuid" == "$uuid" ]]; then
            debug_log "$function_name" "Window '$uuid' exists"
            debug_function_exit "$function_name"
            return 0
        fi
    done

    debug_log "$function_name" "Window '$uuid' does not exist"
    debug_function_exit "$function_name"
    return 1
}

activate_window() {
    local uuid="$1"
    local function_name="activate_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Activate window
    kdotool windowactivate "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' activated."
    debug_function_exit "$function_name"
}

raise_window() {
    local uuid="$1"
    local function_name="raise_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Raise window
    kdotool windowraise "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' raised."
    debug_function_exit "$function_name"
}

move_window() {
    local uuid="$1"
    local x="$2"
    local y="$3"
    local function_name="move_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Move window
    kdotool windowmove "$uuid" "$x" "$y"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' moved to x=$x y=$y."
    debug_function_exit "$function_name"
}

size_window() {
    local uuid="$1"
    local width="$2"
    local height="$3"
    local function_name="size_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Size window
    kdotool windowsize "$uuid" "$width" "$height"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' sized to width=$width height=$height."
    debug_function_exit "$function_name"
}

minimize_window() {
    local uuid="$1"
    local function_name="minimize_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    #Minimize window
    kdotool windowminimize "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' minimized."
    debug_function_exit "$function_name"
}

close_window() {
    local uuid="$1"
    local function_name="close_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Close window
    kdotool windowclose "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' closed."
    debug_function_exit "$function_name"
}
