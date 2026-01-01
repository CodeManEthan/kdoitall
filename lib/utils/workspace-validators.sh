#!/bin/bash

check_and_set_guard "_KDOITALL_WORKSPACE_VALIDATORS_LOADED" || return 0

validate_workspace_name() {
    local workspace_name="$1"
    
    # Check not empty
    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name cannot be empty"
        return 1
    fi
    
    # Check length
    if [[ ${#workspace_name} -gt 50 ]]; then
        echo "Error: Workspace name too long (max 50 characters)"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Workspace name can only contain letters, numbers, hyphens, and underscores"
        return 1
    fi
    
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
        echo "Error: Window name cannot be empty"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check length
    if [[ ${#window_name} -gt 100 ]]; then
        echo "Error: Window name too long (max 100 characters)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$window_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Window name can only contain letters, numbers, hyphens, and underscores"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Window name is valid: $window_name"
    debug_function_exit "$function_name"
    return 0
}