#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_DELETE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

workspace_delete() {
    local workspace_name="$1"
    local workspace_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}.sh"
    local confirm=""
    local function_name="workspace_delete"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        echo "Usage: kdoitall workspace delete <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace exists in database
    if ! db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Prevent deleting an active workspace
    local is_active=""
    is_active=$(db_get_workspace_is_active "$workspace_name")
    if [[ "$is_active" == "1" ]]; then
        echo "Error: Cannot delete workspace '$workspace_name' while it is active." >&2
        echo "Close the workspace first with: kdoitall workspace close $workspace_name" >&3
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_IS_ACTIVE"
    fi

    # Confirm deletion with user
    echo "Are you sure you want to delete workspace '$workspace_name'? (y/n)" >&3
    read -r confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "Cancelled" >&3
        debug_log "$function_name" "Deletion cancelled by user"
        debug_function_exit "$function_name"
        return 0
    fi
    
    debug_log "$function_name" "User confirmed deletion of workspace: $workspace_name"
    
    # Delete from database
    if ! db_delete_workspace "$workspace_name"; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Deleted workspace from database: $workspace_name"
    
    # Delete workspace script file if it exists
    if [[ -f "$workspace_script" ]]; then
        rm "$workspace_script"
        debug_log "$function_name" "Deleted workspace script: $workspace_script"
    else
        debug_log "$function_name" "Workspace script not found (already deleted?): $workspace_script"
    fi
    
    echo "Workspace '$workspace_name' deleted successfully" >&3
    debug_log "$function_name" "Workspace deletion complete"
    debug_function_exit "$function_name"
    return 0
}
