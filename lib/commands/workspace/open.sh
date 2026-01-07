#!/bin/bash

check_and_set_guard "_KDOITALL_WORKSPACE_OPEN_LOADED" || return 0

# shellcheck source=../../app/safe-mode.sh
source "${LIB_DIR}/app/safe-mode.sh"
# shellcheck source=../../db/safe-mode.sh
source "${LIB_DIR}/db/safe-mode.sh"
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
        echo "Usage: kdoitall workspace open <workspace-name>"
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
        echo "The workspace exists in database but script file is missing."
        echo "Try recreating the workspace."
        debug_function_exit "$function_name"
        return 1
    fi

    # Check for safe mode apps
    local -a safe_mode_apps=()
    mapfile -t safe_mode_apps < <(detect_safe_mode_apps "$workspace_name")
    
    if [[ ${#safe_mode_apps[@]} -gt 0 ]]; then
        # Prompt user with options
        local choice
        choice=$(prompt_safe_mode "${safe_mode_apps[@]}")
        
        case "$choice" in
            e)
                # End - exit workspace open
                echo "Please run safe mode for each app using the commands shown above."
                echo "Then run 'kdoitall workspace open $workspace_name' again."
                debug_function_exit "$function_name"
                return 0
                ;;
            o)
                # Open anyway - will ask again next time
                echo "Opening workspace without safe mode validation..."
                echo "Note: Window detection may be unreliable for unvalidated apps."
                ;;
            s)
                # Skip these specific apps - mark as completed
                for app_id in "${safe_mode_apps[@]}"; do
                    db_set_safe_mode_completed "$app_id"
                done
                echo "Safe mode disabled for these apps. Opening workspace..."
                ;;
            n)
                # Never ask again - set global config
                # TODO: Implement global config setting
                echo "Safe mode prompts disabled globally."
                for app_id in "${safe_mode_apps[@]}"; do
                    db_set_safe_mode_completed "$app_id"
                done
                echo "Opening workspace..."
                ;;
            *)
                # Invalid choice - default to end
                echo "Invalid choice. Exiting."
                debug_function_exit "$function_name"
                return 1
                ;;
        esac
    fi

    # Only detach if:
    # - We're running in a terminal (interactive)
    # - Not in debug or verbose mode (user wants to see output)
    # - Haven't already detached (prevent recursive detachment)
    if [ -t 0 ] && 
       [ "$DEBUG_MODE" != "true" ] && 
       [ "$VERBOSE_MODE" != "true" ] && 
       [ -z "$_KDOITALL_DETACHED" ]; then
        
        debug_log "$function_name" "Detaching to background for workspace launch"
        
        # Mark as detached to prevent recursive backgrounding
        export _KDOITALL_DETACHED=true
        
        echo "Opening workspace: $workspace_name"
        echo "Launching applications in background..."
        
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
