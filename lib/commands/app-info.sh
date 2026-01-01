#!/bin/bash

# ============================================================================
# App Info Command
# ============================================================================
# Display detailed information about a specific application

check_and_set_guard "_KDOITALL_APP_INFO_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# app_info()
# Show detailed information about an application
# Parameters:
#   $1 - app_id (required)
# ----------------------------------------------------------------------------
app_info() {
    local function_name="app_info"
    local app_id="$1"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        echo "Error: app_id required"
        echo "Usage: kdoitall app info <app_id>"
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Call the registry info function
    if registry_get_application_info "$app_id"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_get_application_info failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
