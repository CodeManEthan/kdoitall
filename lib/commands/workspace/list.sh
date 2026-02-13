#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_and_set_guard "_KDOITALL_WORKSPACE_LIST_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

workspace_list() {
    local workspaces=""
    local function_name="workspace_list"

    debug_function_enter "$function_name" "$@"

    # Get all workspaces from database
    workspaces=$(db_list_workspaces)

    # Handle empty workspace list
    if [[ -z "$workspaces" ]]; then
        echo "No workspaces defined." >&3
        echo "Create one with: kdoitall workspace create <name>" >&3
        debug_function_exit "$function_name"
        return 0
    fi

    # Display header
    echo "" >&3
    echo "Defined Workspaces:" >&3
    echo "===================" >&3

    # Process each workspace
    while IFS='|' read -r workspace_name description created_at is_active last_opened; do
        local open_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
        local close_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh"

        echo "" >&3
        echo "Workspace: $workspace_name" >&3
        
        # Show description if present
        [[ -n "$description" ]] && echo "Description: $description" >&3
        
        # Show created timestamp
        echo "Created: $created_at" >&3
        
        # Show last opened timestamp if present
        [[ -n "$last_opened" ]] && echo "Last opened: $last_opened" >&3
        
        # Show active status if workspace is currently active
        [[ "$is_active" == "1" || "$is_active" == "TRUE" ]] && echo "Status: ACTIVE" >&3

        # Check if script files exist
        if [[ ! -f "$open_script" || ! -f "$close_script" ]]; then
            echo "⚠️  Warning: Script files missing or incomplete" >&2
            [[ ! -f "$open_script" ]] && echo "   Missing: ${open_script##*/}" >&2
            [[ ! -f "$close_script" ]] && echo "   Missing: ${close_script##*/}" >&2
        fi
    done <<< "$workspaces"

    echo "" >&3
    
    debug_function_exit "$function_name"
    return 0
}
