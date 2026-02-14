#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_VALIDATORS_LOADED" || return 0

validate_workspace_name() {
    local workspace_name="$1"
    local function_name="db_validate_workspace_name"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name provided
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "Usage: kdoitall workspace create <workspace-name>"
        echo "Usage: kdoitall workspace create <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check length
    if [[ ${#workspace_name} -gt 50 ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Workspace name too long (max 50 characters): $workspace_name"
        echo "Workspace name too long (max 50 characters): $workspace_name" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Invalid characters in workspace name: $workspace_name"
        echo "Invalid characters in workspace name: $workspace_name" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Workspace name is valid: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}

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
        debug_error "$function_name" "$ERR_INVALID_WINDOW_NAME" "Window name too long (max 100 characters): $window_name"
        echo "Window name too long (max 100 characters): $window_name" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$window_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_WINDOW_NAME" "Invalid characters in window name: $window_name"
        echo "Invalid characters in window name: $window_name" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Window name is valid: $window_name"
    debug_function_exit "$function_name"
    return 0
}

validate_window_name_unique() {
    local window_name="$1"
    local -n existing_apps_ref="$2"
    local function_name="validate_window_name_unique"

    debug_function_enter "$function_name" "$window_name"

    for app_entry in "${existing_apps_ref[@]}"; do
        local existing_name=""
        existing_name=$(echo "$app_entry" | cut -d'|' -f2)

        if [[ "$existing_name" == "$window_name" ]]; then
            debug_error "$function_name" "$ERR_INVALID_WINDOW_NAME" "Window name already in use: $window_name"
            echo "Window name already in use in this workspace: $window_name" >&3
            debug_function_exit "$function_name"
            return 1
        fi
    done

    debug_log "$function_name" "Window name is unique: $window_name"
    debug_function_exit "$function_name"
    return 0
}
