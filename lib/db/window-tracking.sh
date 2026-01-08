#!/bin/bash

check_and_set_guard "_KDOITALL_DB_WINDOW_TRACKING_LOADED" || return 0

db_get_uuid_by_window_name() {
    local window_name="$1"
    local uuid=""
    local function_name="get_uuid_by_window_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" || return 1

    # Get UUID for Window Name from 'windows' table
    uuid=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        "SELECT uuid FROM app_windows WHERE window_name = :window_name;" 2>/dev/null)

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$window_name' → '$uuid'"
    
    debug_function_exit "$function_name"
    echo "$uuid"
}

db_get_window_name_by_uuid() {
    local uuid="$1"
    local window_name=""
    local function_name="get_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" || return 1

    # Get Window Name for UUID from 'windows' table
    window_name=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :uuid '$uuid'" \
        "SELECT window_name FROM app_windows WHERE uuid = :uuid;" 2>/dev/null)

    if [[ -z "$window_name" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_NAME_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass Window Name
    debug_log "$function_name" "'$uuid' → '$window_name'"

    debug_function_exit "$function_name"
    echo "$window_name"
}

db_get_tab_by_tab_name() {
    local window_name="$1"
    local tab_name="$2"
    local tab_number=""
    local function_name="get_tab_by_tab_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" || return 1
    validate_parameter_pass "$tab_name" || return 1

    # Get Tab Number for Window Name & Tab Name from 'tabs' table
    tab_number=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        -cmd ".param set :tab_name '$tab_name'" \
        "SELECT tab FROM tabs WHERE window_name = :window_name AND tab_name = :tab_name;" 2>/dev/null)

    if [[ -z "$tab_number" ]]; then
        debug_error "$function_name" "$ERR_TAB_NUMBER_NOT_FOUND"  "$window_name - $tab_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass Tab Number
    debug_log "$function_name" "'$window_name' '$tab_name' → '$tab_number'"
    
    debug_function_exit "$function_name"
    echo "$tab_number"
}

db_check_window_exists_by_window_name() {
    local window_name="$1"
    local uuid=""
    local function_name="check_window_exists_by_window_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" || return 1

    # Get UUID by Window Name
    uuid=$(db_get_uuid_by_window_name "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$window_name' ($uuid) already exists."

    debug_function_exit "$function_name"
    echo "$uuid"    
}


db_add_window() {
    local workspace_name="$1"
    local window_name="$2"
    local uuid="$3"
    local class="$4"
    local function_name="db_add_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" || return 1
    validate_parameter_pass "$window_name" || return 1
    validate_parameter_pass "$uuid" || return 1
    validate_parameter_pass "$class" || return 1
    
    # Add entry to 'app_windows' table
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace '$workspace_name'" \
        -cmd ".param set :window '$window_name'" \
        -cmd ".param set :uuid '$uuid'" \
        -cmd ".param set :class '$class'" \
        "INSERT INTO app_windows (workspace_name, window_name, uuid, class, is_tab)
         VALUES (:workspace, :window, :uuid, :class, FALSE);"
    
    debug_log "$function_name" "Added window '$window_name' (workspace: '$workspace_name', uuid: '$uuid', class: '$class')"
    debug_function_exit "$function_name"
}

db_delete_window() {
    local window_name="$1"
    local function_name="db_delete_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" || return 1

    # Delete entry from 'app_windows' table
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window '$window_name'" \
        "DELETE FROM app_windows WHERE window_name = :window;"
    
    debug_log "$function_name" "Deleted window '$window_name'"
    debug_function_exit "$function_name"
}

db_claim_window() {
    local new_workspace_name="$1"
    local new_window_name="$2"
    local uuid="$3"
    local function_name="db_claim_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$new_workspace_name" || return 1
    validate_parameter_pass "$new_window_name" || return 1
    validate_parameter_pass "$uuid" || return 1

    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window '$new_window_name'" \
        -cmd ".param set :workspace '$new_workspace_name'" \
        -cmd ".param set :uuid '$uuid'" \
        "UPDATE app_windows 
         SET window_name = :window,
             workspace_name = :workspace
         WHERE uuid = :uuid;"

    debug_log "$function_name" "Claimed window '$new_window_name' (workspace: '$new_workspace_name', uuid: '$uuid')"
    debug_function_exit "$function_name"
}

db_add_existing_windows() {
    # uuids_ref="$1"
    # classes_ref="$2"
    local window_name=""
    local workspace_name="~auto:workspace"
    local function_name="db_add_existing_windows"

    # Track class counts for unique naming
    declare -A class_counts

    debug_function_enter "$function_name" "$1" "$2"

    validate_name_ref_parameter_pass "$1" "uuids_ref" || return 1
    validate_name_ref_parameter_pass "$2" "classes_ref" || return 1
    local -n uuids_ref="$1"
    local -n classes_ref="$2"
    
    debug_log "$function_name" "===== ARRAYS FROM KDOTOOL ====="

    for i in "${!uuids_ref[@]}"; do
        local class="${classes_ref[$i]}"
        local uuid="${uuids_ref[$i]}"
        
        # Increment counter for this class
        if [[ -z "${class_counts[$class]+_}" ]]; then
            class_counts[$class]=1
        else
            ((class_counts[$class]++))
        fi
        
        # Create unique window name with counter
        window_name="~auto:${class}:${class_counts[$class]}"

        # debug_log "$function_name" "Attempting INSERT: window_name='$window_name', uuid='$uuid', class='$class'"

        # Check if UUID already exists first
        local existing_check=""
        existing_check=$(sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :uuid '$uuid'" \
            "SELECT window_name FROM app_windows WHERE uuid = :uuid;" 2>/dev/null)
        
        if [[ -n "$existing_check" ]]; then
            # debug_log "$function_name" "UUID ALREADY IN DB: uuid='$uuid' exists as window_name='$existing_check'"
            continue
        fi

        local changes=""
        changes=$(sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :workspace '$workspace_name'" \
            -cmd ".param set :window '$window_name'" \
            -cmd ".param set :uuid '$uuid'" \
            -cmd ".param set :class '$class'" \
            "INSERT OR IGNORE INTO app_windows (workspace_name, window_name, uuid, class, is_tab) 
            VALUES (:workspace, :window, :uuid, :class, FALSE);
            SELECT changes();")
        
        if [ "$changes" -eq 1 ]; then
            debug_log "$function_name" "✓ INSERTED: window_name='$window_name', uuid='$uuid', class='$class'"
        else
            debug_log "$function_name" "✗ INSERT FAILED (window_name conflict?): window_name='$window_name', uuid='$uuid'"
        fi
    done

    debug_function_exit "$function_name"
}

db_delete_stale_windows() {
    # existing_uuids_ref="$1"
    # db_uuids_ref="$2"
    local -A existing_lookup=()
    local uuid_to_delete=""
    local function_name="db_delete_stale_windows"

    debug_function_enter "$function_name" "$1" "$2"

    local -n existing_uuids_ref="$1"
    local -n db_uuids_ref="$2"
    validate_name_ref_parameter_pass "$1" "uuids_ref" || return 1
    validate_name_ref_parameter_pass "$2" "classes_ref" || return 1

    # Build lookup table for O(1) checking
    for uuid in "${existing_uuids_ref[@]}"; do
        existing_lookup["$uuid"]=1
    done
    
    debug_log "$function_name" "Built lookup table with ${#existing_lookup[@]} entries"
    
    # Delete UUIDs that don't exist anymore
    for uuid_to_delete in "${db_uuids_ref[@]}"; do
        if [[ ! -v existing_lookup[$uuid_to_delete] ]]; then
            sqlite3 "$KDOITALL_DB" \
                -cmd ".param init" \
                -cmd ".param set :uuid '$uuid_to_delete'" \
                "DELETE FROM app_windows WHERE uuid = :uuid;"
            
            # Check if row was actually deleted
            local changes=""
            changes=$(sqlite3 "$KDOITALL_DB" "SELECT changes()")
            
            if [ "$changes" -eq 1 ]; then
                debug_log "$function_name" "DELETED: Stale window with uuid='$uuid_to_delete'"
                echo "Deleted stale window: $uuid_to_delete"
            else
                debug_log "$function_name" "DELETE FAILED: uuid='$uuid_to_delete' not found in database"
            fi
        else
            debug_log "$function_name" "KEPT: uuid='$uuid_to_delete' still exists"
        fi
    done

    debug_function_exit "$function_name"
}