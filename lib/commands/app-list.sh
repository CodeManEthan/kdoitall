#!/bin/bash

# ============================================================================
# App List Command
# ============================================================================
# Lists applications from the registry with optional filtering

check_and_set_guard "_KDOITALL_APP_LIST_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# app_list()
# List applications from registry
# Parameters:
#   $1 - filter (optional: all, terminal, desktop, both) - default: all
# ----------------------------------------------------------------------------
app_list() {
    local function_name="app_list"
    local filter="${1:-all}"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate filter parameter
    case "$filter" in
        all|terminal|desktop|both)
            debug_log "$function_name" "Listing applications with filter: $filter"
            ;;
        *)
            echo "Error: Invalid filter: $filter"
            echo "Valid filters: all, terminal, desktop, both"
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid filter: $filter"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # Call the registry list function
    if registry_list_applications "$filter"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_list_applications failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
