#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_CLOSE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

workspace_close() {
    local workspace_name="$1"
    local close_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh"
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
    
    # Check if close script file exists
    if [[ ! -f "$close_script" ]]; then
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$close_script"
        echo "Error: Close script not found: $close_script" >&2
        echo "The workspace exists in database but script file is missing." >&3
        echo "Try recreating the workspace." >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "Closing workspace: $workspace_name" >&3
    debug_log "$function_name" "Executing close script: $close_script"
    
    # Source and execute the script
    # shellcheck source=/dev/null
    source "$close_script"
    
    # Update database metadata to mark workspace as inactive
    db_set_workspace_active "$workspace_name" "FALSE"
    
    echo "Workspace '$workspace_name' closed successfully" >&3
    debug_log "$function_name" "Workspace closed and database updated"
    debug_function_exit "$function_name"
    return 0
}
