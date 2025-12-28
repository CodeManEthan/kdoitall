#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh
# core/database.sh
# window_management/desktop.sh
# window_management/screen.sh
# window_management/window.sh
# window_management/tab.sh

check_and_set_guard "_KDOITALL_CORE_LOADED" || return 0

# shellcheck source=../window-management/desktop.sh
source "${LIB_DIR}/window-management/desktop.sh"
# shellcheck source=../window-management/screen.sh
source "${LIB_DIR}/window-management/screen.sh"
# shellcheck source=../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"
# shellcheck source=../window-management/tab.sh
source "${LIB_DIR}/window-management/tab.sh"

launch_window() {
    local window_name="$1"
    local class="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local launch_mode="$6"
    local launch_command="$7"
    
    shift 7
    
    local window_title=""
    local workspace_name="default_workspace"
    local function_name="launch_window"
 
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --window-title)
                window_title="$2"
                shift 2
                ;;
            --workspace-name)
                workspace_name="$2"
                shift 2
                ;;
            *)
                echo "Unknown parameter: $1"
                return 1
                ;;
        esac
    done
    
    local uuid

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Refresh database with current windows
    auto_detect_windows

    debug_log "$function_name: Check Window Exists (If SINGLE or UNIQUE Launch Mode.)"
    # Check Window Exists (If SINGLE or UNIQUE Launch Mode)
    if [[ "$launch_mode" == "$LAUNCH_MODE_UNIQUE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE" ]]; then
        uuid=$(check_window_exists "$window_title" "$class")
    fi

    # Launch Window
    if [ -n "$uuid" ]; then
        debug_log "$function_name: Activate Window"
        activate_window --uuid "$uuid"

        # Claim Window in Database
        db_claim_window "$window_name" "$workspace_name" "$uuid"
    else
        debug_log "$function_name: Launch Window"
        eval "$launch_command"
        uuid=$(get_last_launched_uuid_by_class "$class")

        # Add Window to Database
        debug_log "$function_name: Add Window to Database"
        db_add_window "$window_name" "$workspace_name" "$uuid" "$class" 
    fi

    # Move Window to Desktop
    debug_log "$function_name: Move Window to Desktop"
    move_window_to_desktop "$desktop" --uuid "$uuid"

    # Move Window to Screen
    debug_log "$function_name: Move Window to Screen"
    move_active_window_to_screen "$screen"

    # Move Window to Position
    debug_log "$function_name: Move Window to Position"
    move_window_to_position "$screen" "$position" --uuid "$uuid"

    
}

close_window() {
    local window_name="$1"
    local uuid

    uuid=$(db_get_uuid_by_window_name "$window_name") || return 1

    close_window --uuid "$uuid"

    db_delete_window "$window_name"
}

auto_detect_windows() {
    local existing_uuids=()
    local existing_classes=()
    local db_uuids=()
    local function_name="auto_detect_windows"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    # Get all currently existing window UUIDs
    mapfile -t existing_uuids < <(get_existing_windows_uuid)

    # Get all currently existing window classes
    # shellcheck disable=SC2034
    mapfile -t existing_classes < <(get_existing_windows_class_by_uuid "${existing_uuids[@]}")
    
    # Get all UUIDs from the database
    # shellcheck disable=SC2034
    mapfile -t db_uuids < <(sqlite3 "$KDOITALL_DB" "SELECT uuid FROM app_windows WHERE uuid IS NOT NULL")
    
    # Add new windows to database
    db_add_existing_windows existing_uuids existing_classes
    
    # Delete stale windows from database
    db_delete_stale_windows existing_uuids db_uuids
}


