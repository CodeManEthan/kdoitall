#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_INFO_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

workspace_info() {
    local workspace_name="$1"
    local workspace_data=""
    local function_name="workspace_info"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name required" >&2
        echo "Usage: kdoitall workspace info <name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate workspace exists
    if ! db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' not found" >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Get workspace metadata
    workspace_data=$(db_get_workspace "$workspace_name")

    local description=""
    local created_at=""
    local is_active=""
    local last_opened=""
    IFS='|' read -r _ description created_at is_active last_opened <<< "$workspace_data"

    # Display workspace metadata
    echo "" >&3
    echo "Workspace: $workspace_name" >&3
    echo "===================" >&3

    [[ -n "$description" ]] && echo "Description: $description" >&3

    echo "Created: $created_at" >&3

    [[ -n "$last_opened" ]] && echo "Last opened: $last_opened" >&3

    [[ "$is_active" == "1" || "$is_active" == "TRUE" ]] && echo "Status: ACTIVE" >&3

    # Display detailed window configuration
    display_workspace_windows "$workspace_name"

    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}
