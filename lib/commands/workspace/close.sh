#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_CLOSE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

workspace_close() {
    local workspace_name="$1"
    local workspace_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}.sh"
    local function_name="workspace_close"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        echo "Usage: kdoitall workspace close <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace exists in database
    if ! db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace script file exists
    if [[ ! -f "$workspace_script" ]]; then
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$workspace_script"
        echo "Error: Workspace script not found: $workspace_script" >&2
        echo "The workspace exists in database but script file is missing." >&3
        echo "Try recreating the workspace." >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Executing workspace script: $workspace_script"
    
    # Source the workspace script and call the close function
    # shellcheck source=/dev/null
    source "$workspace_script"
    
    local close_func_name=""
    close_func_name="close_workspace_${workspace_name//-/_}"
    "$close_func_name"
    
    # Update database metadata to mark workspace as inactive
    db_set_workspace_active "$workspace_name" "FALSE"
    
    debug_log "$function_name" "Workspace closed and database updated"
    debug_function_exit "$function_name"
    return 0
}
