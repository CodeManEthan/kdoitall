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
    local desktop="$2"
    local screen="$3"
    local position="$4"
    local launch_mode="$5"
    local launch_type="$6"
    local launch_command=""
    local app_id=""
    local window_title=""
    local workspace_name="default_workspace"
    local function_name="launch_window"
    local uuid=""
    local class=""

    debug_function_enter "$function_name" "$@"
    
    shift 6
 
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --launch-command)
                launch_command="$2"
                shift 2
                ;;
            --app-id)
                app_id="$2"
                shift 2
                ;;
            --window-title)
                window_title="$2"
                shift 2
                ;;
            --workspace-name)
                workspace_name="$2"
                shift 2
                ;;
            *)
                debug_error "$function_name" "$ERR_INVALID_PARAMETER" "$1"
                debug_function_exit "$function_name"
                return 1
                ;;
        esac
    done

    # Try to retrieve stored app_class from database
    if [[ -n "$app_id" ]]; then
        class=$(db_get_app_class "$app_id")
        if [[ -n "$class" ]]; then
            debug_log "$function_name" "Retrieved stored app_class: $class"
        else
            debug_log "$function_name" "No stored app_class yet for $app_id, will detect after launch"
        fi
    fi

    # Refresh database with current windows
    debug_log "$function_name" "Auto Detect Windows"
    auto_detect_windows

    
    # Check Window Exists (If SINGLE or UNIQUE Launch Mode)
    if [[ "$launch_mode" == "$LAUNCH_MODE_UNIQUE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE" ]]; then
        debug_log "$function_name" "Check Window Exists"
        uuid=$(check_window_exists_by_window_title_and_class "$window_title" "$class")
    fi

    # Launch Window
    if [[ -n "$uuid" && ( "$launch_mode" == "$LAUNCH_MODE_UNIQUE" || "$launch_mode" == "$LAUNCH_MODE_SINGLE" ) ]]; then
        debug_log "$function_name" "Window already exists - $uuid."

        # Claim Window in Database
        debug_log "$function_name" "Claim Window in app_windows table."
        db_claim_window "$window_name" "$workspace_name" "$uuid"
    else
        debug_log "$function_name" "Launch Window"

        if [[ -n "$launch_command" && "$launch_type" == "$LAUNCH_TYPE_TERMINAL" ]]; then
            eval "$launch_command"
        elif [[ "$launch_type" == "$LAUNCH_TYPE_DESKTOP" ]]; then
            launch_desktop_window "$app_id"
        fi

        sleep "$LAUNCH_DELAY"
        uuid=$(get_uuid_by_process_of_elimination "$class")

        # Detect and store app_class if not already stored
        if [[ -n "$app_id" && -z "$class" ]]; then
            debug_log "$function_name" "Detecting app_class for $app_id..."
            
            # Detect actual window class from the launched window
            local detected_class=""
            detected_class=$(get_window_class_by_uuid "$uuid")
            
            if [[ -n "$detected_class" ]]; then
                # Store in database for future use
                if db_set_app_class "$app_id" "$detected_class"; then
                    class="$detected_class"
                    debug_log "$function_name" "✓ Auto-detected and stored app_class: $detected_class"
                else
                    debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to store app_class: $detected_class"
                fi
            else
                debug_error "$function_name" "$ERR_CLASS_DETECTION_FAILED" "Could not detect class for UUID $uuid"
            fi
        fi

        # Add Window to Database
        debug_log "$function_name" "Add Window to app_windows table."
        db_add_window "$window_name" "$workspace_name" "$uuid" "$class" 
    fi

    # Move Window to Desktop
    debug_log "$function_name" "Move Window to Desktop"
    move_window_to_desktop_by_uuid "$uuid" "$desktop"

    # Move Window to Screen
    debug_log "$function_name" "Move Window to Screen"
    move_window_to_screen_by_uuid "$uuid" "$screen"

    # Move Window to Position
    debug_log "$function_name" "Move Window to Position"
    move_window_to_position_by_uuid "$uuid" "$screen" "$position"

    debug_function_exit "$function_name"
}

close_window() {
    local window_name="$1"
    local uuid=""
    local function_name="close-window"

    debug_function_enter "$function_name" "$@"

    uuid=$(db_get_uuid_by_window_name "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    close_window_by_uuid "$uuid"

    db_delete_window "$window_name"

    debug_function_exit "$function_name"
}

auto_detect_windows() {
    local -a existing_uuids=()
    local -a existing_classes=()
    local -a db_uuids=()
    local function_name="auto_detect_windows"

    debug_function_enter "$function_name"
    
    # Get all currently existing window UUIDs
    debug_log "$function_name" "===== GET WINDOWS FROM KDOTOOL ====="
    mapfile -t existing_uuids < <(get_existing_windows_uuid)

    # Get all currently existing window classes
    debug_log "$function_name" "===== GET CLASSES FROM KDOTOOL ====="
    # shellcheck disable=SC2034
    mapfile -t existing_classes < <(get_existing_windows_class_by_uuids "${existing_uuids[@]}")
    
    # Get all UUIDs from the database
    debug_log "$function_name" "===== GET UUIDS FROM DATABASE ====="
    # shellcheck disable=SC2034
    mapfile -t db_uuids < <(sqlite3 "$KDOITALL_DB" "SELECT uuid FROM app_windows WHERE uuid IS NOT NULL")

    debug_log "$function_name" "===== KDOTOOL RESULTS ====="
    debug_array existing_uuids
    debug_array existing_classes
    
    debug_log "$function_name" "===== DATABASE RESULTS ====="
    debug_array db_uuids

    # Delete stale windows from database
    debug_log "$function_name" "===== DELETE STALE WINDOWS ====="
    db_delete_stale_windows existing_uuids db_uuids
    
    # Add new windows to database
    debug_log "$function_name" "===== ADD NEW WINDOWS ====="
    db_add_existing_windows existing_uuids existing_classes

    debug_function_exit "$function_name"
}


launch_desktop_window() {
    local app_id="$1"
    local launch_command=""

    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    launch_command="gtk-launch $app_id"

    eval "$launch_command"
}
