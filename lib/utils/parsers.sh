#!/bin/bash

# Sources: 
# core/debug.sh
# core/error_codes.sh
# core/database.sh

# Parse and resolve window identifiers
parse_window_identifiers() {
    local uuid=""
    local window_name=""
    local function_name="parse_window_identifiers"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uuid)
                uuid="$2"
                shift 2
                ;;
            --window-name)
                window_name="$2"
                shift 2
                ;;
            *)
                debug_log "$function_name: ${ERROR_MESSAGES[$ERR_INVALID_PARAMETER]} - $1"
                return 1
                ;;
        esac
    done
    
    # Ensure at least one identifier was provided
    if [[ -z "$uuid" && -z "$window_name" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_MISSING_WINDOW_IDENTIFIER_PARAMETER]}"
        return 1
    fi
    
    # Resolve the missing identifier
    if [[ -n "$uuid" && -z "$window_name" ]]; then
        window_name=$(get_window_name_by_uuid "$uuid") || return 1
        debug_log "$function_name: Resolved window name from $uuid: '$window_name'" "verbose"
    elif [[ -n "$window_name" && -z "$uuid" ]]; then
        uuid=$(get_uuid_by_window_name "$window_name") || return 1
        debug_log "$function_name: Resolved UUID from $window_name: $uuid" "verbose"
    fi
    
    # Output both identifiers
    echo "${uuid}|${window_name}"
}