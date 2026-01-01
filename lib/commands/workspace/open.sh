#!/bin/bash

# ============================================================================
# Workspace Open Command
# ============================================================================
# Opens a workspace by executing its open script

check_and_set_guard "_KDOITALL_WORKSPACE_OPEN_LOADED" || return 0

# ============================================================================
# workspace_open()
# Open a workspace by executing its open script
# ============================================================================
# Parameters:
#   $1 - workspace_name (required)
# Returns: 0 on success, 1 on error
# ============================================================================
workspace_open() {
    local workspace_name="$1"
    local open_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
    local function_name="workspace_open"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name required"
        echo "Usage: kdoitall workspace open <workspace-name>"
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
    
    # Check if open script file exists
    if [[ ! -f "$open_script" ]]; then
        echo "Error: Open script not found: $open_script"
        echo "The workspace exists in database but script file is missing."
        echo "Try recreating the workspace."
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$open_script"
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "Opening workspace: $workspace_name"
    debug_log "$function_name" "Executing open script: $open_script"
    
    # Source and execute the script
    # shellcheck source=/dev/null
    source "$open_script"
    
    # Update database metadata
    db_set_workspace_active "$workspace_name" "TRUE"
    db_update_workspace_last_opened "$workspace_name"
    
    echo "Workspace '$workspace_name' opened successfully"
    debug_log "$function_name" "Workspace opened and database updated"
    debug_function_exit "$function_name"
    return 0
}
