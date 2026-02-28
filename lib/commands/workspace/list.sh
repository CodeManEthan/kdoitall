#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_LIST_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

workspace_list() {
    local show_details="false"
    local workspaces=""
    local function_name="workspace_list"

    debug_function_enter "$function_name" "$@"

    # Sync active flags: deactivate workspaces with no live windows
    db_deactivate_empty_workspaces > /dev/null

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --details)
                show_details="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Get all workspaces from database
    workspaces=$(db_list_workspaces)

    # Handle empty workspace list
    if [[ -z "$workspaces" ]]; then
        echo "No workspaces defined." >&3
        echo "Create one with: kdoitall workspace create <n>" >&3
        debug_function_exit "$function_name"
        return 0
    fi

    # Display header
    echo "" >&3
    echo "Defined Workspaces:" >&3
    echo "===================" >&3

    # Process each workspace
    while IFS='|' read -r workspace_name description created_at is_active last_opened; do
        local workspace_script=""
        workspace_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}.sh"

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

        # Show window information
        if [[ "$show_details" == "true" ]]; then
            display_workspace_windows "$workspace_name"
        else
            display_workspace_applications "$workspace_name"
        fi

        # Check if script file exists
        if [[ ! -f "$workspace_script" ]]; then
            echo "⚠️  Warning: Script file missing: ${workspace_script##*/}" >&2
        fi
    done <<< "$workspaces"

    echo "" >&3
    
    debug_function_exit "$function_name"
    return 0
}
