#!/bin/bash

check_and_set_guard "_KDOITALL_WORKSPACE_VALIDATORS_LOADED" || return 0

validate_workspace_name() {
    local workspace_name="$1"
    local function_name="db_validate_workspace_name"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name provided
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "Usage: kdoitall workspace create <workspace-name>"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check length
    if [[ ${#workspace_name} -gt 50 ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Workspace name too long (max 50 characters): $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Invalid characters in workspace name: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Workspace name is valid: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}

# ----------------------------------------------------------------------------
# validate_window_name()
# Validate window name format
# Parameters:
#   $1 - window_name
# Returns: 0 if valid, 1 if invalid
# ----------------------------------------------------------------------------
validate_window_name() {
    local window_name="$1"
    local function_name="validate_window_name"
    
    debug_function_enter "$function_name" "$@"
    
    # Check not empty
    if [[ -z "$window_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "window_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check length
    if [[ ${#window_name} -gt 100 ]]; then
        debug_error "$function_name" "$ERR_INVALID_WINDOW_NAME" "Workspace name too long (max 50 characters): $window_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$window_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_WINDOW_NAME" "Invalid characters in workspace name: $window_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Window name is valid: $window_name"
    debug_function_exit "$function_name"
    return 0
}