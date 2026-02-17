#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_OPEN_LOADED" || return 0

# shellcheck source=../../app/safe-mode.sh
source "${LIB_DIR}/app/safe-mode.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

workspace_open() {
    local workspace_name="$1"
    local open_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
    local function_name="workspace_open"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        echo "Usage: kdoitall workspace open <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace exists in database
    if ! db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if open script file exists
    if [[ ! -f "$open_script" ]]; then
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$open_script"
        echo "The workspace exists in database but script file is missing." >&3
        echo "Try recreating the workspace." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Check for safe mode apps (skip if prompting is disabled)
    if [[ "${SAFE_MODE_PROMPTING:-enabled}" == "enabled" ]]; then
        local -a safe_mode_apps=()
        mapfile -t safe_mode_apps < <(detect_safe_mode_apps "$workspace_name")

        if [[ ${#safe_mode_apps[@]} -gt 0 && -n "${safe_mode_apps[0]}" ]]; then
            local prompt_result
            prompt_result=$(prompt_safe_mode "${safe_mode_apps[@]}")

            case "$prompt_result" in
                accept)
                    # Re-detect remaining apps (some may have been skipped in disable menu)
                    local -a remaining_apps=()
                    mapfile -t remaining_apps < <(detect_safe_mode_apps "$workspace_name")

                    if [[ ${#remaining_apps[@]} -gt 0 && -n "${remaining_apps[0]}" ]]; then
                        echo "" >&3
                        echo "Starting safe mode for ${#remaining_apps[@]} application(s)..." >&3

                        for app_id in "${remaining_apps[@]}"; do
                            safe_mode_launch_and_detect "$app_id" || true
                        done
                    fi

                    echo "" >&3
                    echo "Proceeding to open workspace..." >&3
                    ;;
                skip|open)
                    # Skip: open without safe-mode (will ask again next time for skip)
                    # Open: apps were disabled/skipped via D menu, proceed directly
                    ;;
                quit)
                    echo "Workspace open cancelled." >&3
                    debug_function_exit "$function_name"
                    return 0
                    ;;
            esac
        fi
    fi

    # Only detach if:
    # - We're running in a terminal (interactive)
    # - Not in debug or verbose mode (user wants to see output)
    # - Haven't already detached (prevent recursive detachment)
    if [ -t 0 ] && 
       [ "$VERBOSE_MODE" != "true" ] && 
       [ -z "$_KDOITALL_DETACHED" ]; then
        
        debug_log "$function_name" "Detaching to background for workspace launch"
        
        # Mark as detached to prevent recursive backgrounding
        export _KDOITALL_DETACHED=true
        
        echo "Opening workspace: $workspace_name" >&3
        echo "Launching applications in background..." >&3
        
        # Execute workspace script in background with nohup
        # This allows the terminal to be closed without killing the processes
        nohup bash -c "
            # Re-source the kdoitall environment
            source '$KDOITALL_INSTALL_DIR/lib/init.sh'
            
            # Source and execute the workspace script
            source '$open_script'
            
            # Update database metadata
            sqlite3 '$KDOITALL_DB' \"UPDATE workspaces SET is_active = 'TRUE', last_opened = datetime('now') WHERE name = '$workspace_name'\"
        " > /dev/null 2>&1 &
        
        debug_log "$function_name" "Workspace script backgrounded (PID: $!)"
        debug_function_exit "$function_name"
        return 0
    fi
    
    echo "Opening workspace: $workspace_name" >&3
    debug_log "$function_name" "Executing open script: $open_script"
    
    # Source and execute the script
    # shellcheck source=/dev/null
    source "$open_script"
    
    # Update database metadata
    db_set_workspace_active "$workspace_name" "TRUE"
    db_set_workspace_last_opened "$workspace_name"
    
    echo "Workspace '$workspace_name' opened successfully" >&3
    debug_log "$function_name" "Workspace opened and database updated"
    debug_function_exit "$function_name"
    return 0
}
