#!/bin/bash

# ============================================================================
# App Options Command
# ============================================================================
# Display launch options for a specific application

check_and_set_guard "_KDOITALL_APP_OPTIONS_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# app_options()
# Show launch options for an application
# Parameters:
#   $1 - app_id (required)
# ----------------------------------------------------------------------------
app_options() {
    local function_name="app_options"
    local app_id="$1"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        echo "Error: app_id required"
        echo "Usage: kdoitall app options <app_id>"
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Call the registry launch options function
    if registry_get_launch_options "$app_id"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_get_launch_options failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
