#!/bin/bash

# ============================================================================
# Workspace Delete Command
# ============================================================================
# Deletes a workspace from database and removes its script files

check_and_set_guard "_KDOITALL_WORKSPACE_DELETE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

# ============================================================================
# workspace_delete()
# Delete a workspace and its associated script files
# ============================================================================
# Parameters:
#   $1 - workspace_name (required)
# Returns: 0 on success, 1 on error or cancellation
# ============================================================================
workspace_delete() {
    local workspace_name="$1"
    local open_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
    local close_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh"
    local confirm=""
    local function_name="workspace_delete"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name required"
        echo "Usage: kdoitall workspace delete <workspace-name>"
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace exists in database
    if ! db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' not found"
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Confirm deletion with user
    echo "Are you sure you want to delete workspace '$workspace_name'? (y/n)"
    read -r confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "Cancelled"
        debug_log "$function_name" "Deletion cancelled by user"
        debug_function_exit "$function_name"
        return 0
    fi
    
    debug_log "$function_name" "User confirmed deletion of workspace: $workspace_name"
    
    # Delete from database
    if ! db_delete_workspace "$workspace_name"; then
        echo "Error: Failed to delete workspace from database"
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Deleted workspace from database: $workspace_name"
    
    # Delete open script file if it exists
    if [[ -f "$open_script" ]]; then
        rm "$open_script"
        debug_log "$function_name" "Deleted open script: $open_script"
    else
        debug_log "$function_name" "Open script not found (already deleted?): $open_script"
    fi
    
    # Delete close script file if it exists
    if [[ -f "$close_script" ]]; then
        rm "$close_script"
        debug_log "$function_name" "Deleted close script: $close_script"
    else
        debug_log "$function_name" "Close script not found (already deleted?): $close_script"
    fi
    
    echo "Workspace '$workspace_name' deleted successfully"
    debug_log "$function_name" "Workspace deletion complete"
    debug_function_exit "$function_name"
    return 0
}
