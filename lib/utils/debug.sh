#!/bin/bash

# Check for debug mode in arguments or environment
DEBUG_MODE=false
VERBOSE_MODE=false

# Check command line args
for arg in "$@"; do
    if [[ "$arg" == "--debug" ]]; then
        DEBUG_MODE=true
    elif [[ "$arg" == "--verbose" ]]; then
        DEBUG_MODE=true
        VERBOSE_MODE=true
    fi
done

debug_log() {
    local message="$1"
    local level="${2:-error}"  # Default to "error" level
    
    if [[ "$level" == "verbose" ]]; then
        # Only show in verbose mode
        if [ "$VERBOSE_MODE" = "true" ]; then
            echo "[DEBUG $(date +%H:%M:%S.%3N)] $message" >&2
        fi
    else
        # Show in both debug and verbose modes (errors)
        if [ "$DEBUG_MODE" = "true" ]; then
            echo "[DEBUG $(date +%H:%M:%S.%3N)] $message" >&2
        fi
    fi
}

debug_array() {
    local array_name="$1"
    local level="${2:-error}"  # Default to "error" level
    
    # Check if we should display based on mode
    local should_display=false
    if [[ "$level" == "verbose" ]]; then
        [ "$VERBOSE_MODE" = "true" ] && should_display=true
    else
        [ "$DEBUG_MODE" = "true" ] && should_display=true
    fi
    
    if [ "$should_display" = "true" ]; then
        # Use nameref to reference the array by name
        local -n array_ref="$array_name"
        
        echo "[DEBUG $(date +%H:%M:%S.%3N)] Array '$array_name' (${#array_ref[@]} elements):" >&2
        
        if [ "${#array_ref[@]}" -eq 0 ]; then
            echo "[DEBUG $(date +%H:%M:%S.%3N)]   (empty)" >&2
        else
            local i
            for i in "${!array_ref[@]}"; do
                echo "[DEBUG $(date +%H:%M:%S.%3N)]   [$i] = '${array_ref[$i]}'" >&2
            done
        fi
    fi
}

debug_app_windows() {
    local level="${1:-error}"  # Default to "error" level
    
    # Check if we should display based on mode
    local should_display=false
    if [[ "$level" == "verbose" ]]; then
        [ "$VERBOSE_MODE" = "true" ] && should_display=true
    else
        [ "$DEBUG_MODE" = "true" ] && should_display=true
    fi
    
    if [ "$should_display" = "true" ]; then
        local count
        count=$(sqlite3 "$KDOITALL_DB" "SELECT COUNT(*) FROM app_windows" 2>/dev/null || echo "0")
        
        echo "[DEBUG $(date +%H:%M:%S.%3N)] app_windows table ($count rows):" >&2
        
        if [ "$count" -eq 0 ]; then
            echo "[DEBUG $(date +%H:%M:%S.%3N)]   (empty)" >&2
        else
            # Header
            echo "[DEBUG $(date +%H:%M:%S.%3N)]   workspace_name | window_name | uuid | class | is_tab" >&2
            echo "[DEBUG $(date +%H:%M:%S.%3N)]   " "$(printf '%.0s-' {1..80})" >&2
            
            # Rows
            sqlite3 "$KDOITALL_DB" "SELECT workspace_name, window_name, uuid, class, is_tab FROM app_windows" | while IFS='|' read -r workspace window uuid class is_tab; do
                echo "[DEBUG $(date +%H:%M:%S.%3N)]   $workspace | $window | $uuid | $class | $is_tab" >&2
            done
        fi
    fi
}

# Debug function to show chord keys being pressed (verbose only)
debug_chord() {
    if [ "$VERBOSE_MODE" = "true" ]; then
        local keys=("$@")
        local chord_string=""
        
        for key in "${keys[@]}"; do
            if [[ -z "$chord_string" ]]; then
                chord_string="$key"
            else
                chord_string="$chord_string + $key"
            fi
        done
        
        debug_log "CHORD: $chord_string" "verbose"
    fi
}

export DEBUG_MODE VERBOSE_MODE
export -f debug_log
export -f debug_array
export -f debug_app_windows
export -f debug_chord