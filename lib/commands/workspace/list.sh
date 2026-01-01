#!/bin/bash

# ============================================================================
# Workspace List Command
# ============================================================================
# Lists all defined workspaces with metadata and status information

check_and_set_guard "_KDOITALL_WORKSPACE_LIST_LOADED" || return 0

# ============================================================================
# workspace_list()
# List all defined workspaces with their metadata
# ============================================================================
# Parameters: None
# Returns: 0 (always succeeds, even if no workspaces)
# ============================================================================
workspace_list() {
    local workspaces=""
    local function_name="workspace_list"

    debug_function_enter "$function_name" "$@"

    # Get all workspaces from database
    workspaces=$(db_list_workspaces)

    # Handle empty workspace list
    if [[ -z "$workspaces" ]]; then
        echo "No workspaces defined."
        echo "Create one with: kdoitall workspace create <name>"
        debug_function_exit "$function_name"
        return 0
    fi

    # Display header
    echo ""
    echo "Defined Workspaces:"
    echo "==================="

    # Process each workspace
    while IFS='|' read -r workspace_name description created_at is_active last_opened; do
        local open_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
        local close_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh"

        echo ""
        echo "Workspace: $workspace_name"
        
        # Show description if present
        [[ -n "$description" ]] && echo "Description: $description"
        
        # Show created timestamp
        echo "Created: $created_at"
        
        # Show last opened timestamp if present
        [[ -n "$last_opened" ]] && echo "Last opened: $last_opened"
        
        # Show active status if workspace is currently active
        [[ "$is_active" == "1" || "$is_active" == "TRUE" ]] && echo "Status: ACTIVE"

        # Check if script files exist
        if [[ ! -f "$open_script" || ! -f "$close_script" ]]; then
            echo "⚠️  Warning: Script files missing or incomplete"
            [[ ! -f "$open_script" ]] && echo "   Missing: ${open_script##*/}"
            [[ ! -f "$close_script" ]] && echo "   Missing: ${close_script##*/}"
        fi
    done <<< "$workspaces"

    echo ""
    
    debug_function_exit "$function_name"
    return 0
}
