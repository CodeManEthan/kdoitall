#!/bin/bash

check_and_set_guard "_KDOITALL_WORKSPACE_VALIDATORS_LOADED" || return 0

validate_workspace_name() {
    local name="$1"
    
    # Check not empty
    if [[ -z "$name" ]]; then
        echo "Error: Workspace name cannot be empty"
        return 1
    fi
    
    # Check length
    if [[ ${#name} -gt 50 ]]; then
        echo "Error: Workspace name too long (max 50 characters)"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Workspace name can only contain letters, numbers, hyphens, and underscores"
        return 1
    fi
    
    return 0
}

validate_window_name() {
    local name="$1"
    
    # Similar validation to workspace name
    if [[ -z "$name" ]]; then
        echo "Error: Window name cannot be empty"
        return 1
    fi
    
    if [[ ${#name} -gt 100 ]]; then
        echo "Error: Window name too long (max 100 characters)"
        return 1
    fi
    
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Window name can only contain letters, numbers, hyphens, and underscores"
        return 1
    fi
    
    return 0
}