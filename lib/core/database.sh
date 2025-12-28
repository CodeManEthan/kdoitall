#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh

db_get_uuid_by_window_name() {
    local window_name="$1"
    local uuid
    local function_name="get_uuid_by_window_name"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Get UUID for Window Name from 'windows' table
    uuid=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        "SELECT uuid FROM windows WHERE window_name = :window_name;" 2>/dev/null)

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    debug_log "$function_name: '$window_name' → '$uuid'" "verbose"
    
    # Pass UUID
    echo "$uuid"
}

db_get_window_name_by_uuid() {
    local uuid="$1"
    local window_name
    local function_name="get_window_by_uuid"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Get Window Name for UUID from 'windows' table
    window_name=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :uuid '$uuid'" \
        "SELECT window_name FROM windows WHERE uuid = :uuid;" 2>/dev/null)

    if [[ -z "$window_name" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_WINDOW_NAME_NOT_FOUND]} - $uuid"
        return 1
    fi

    debug_log "$function_name: '$uuid' → '$window_name'" "verbose"

    # Pass Window Name
    echo "$window_name"
}

db_get_tab_by_tab_name() {
    local window_name="$1"
    local tab_name="$2"
    local tab_number
    local function_name="get_tab_by_tab_name"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Get Tab Number for Window Name & Tab Name from 'tabs' table
    tab_number=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        -cmd ".param set :tab_name '$tab_name'" \
        "SELECT tab FROM tabs WHERE window_name = :window_name AND tab_name = :tab_name;" 2>/dev/null)

    if [[ -z "$tab_number" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_TAB_NUMBER_NOT_FOUND]} - $window_name - $tab_name"
        return 1
    fi

    debug_log "$function_name: '$window_name' '$tab_name' → '$tab_number'" "verbose"
    
    # Pass Tab Number
    echo "$tab_number"
}

db_check_window_exists_by_window_name() {
    local window_name="$1"
    local uuid
    local function_name="check_window_exists_by_window_name"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Get UUID by Window Name
    uuid=$(db_get_uuid_by_window_name "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_UUID_NOT_FOUND]} - $window_name"
        return 1
    fi

    debug_log "'$window_name' ($uuid) already exists." "verbose"

    # Pass UUID
    echo "$uuid"    
}


db_add_window() {
    local window_name="$1"
    local workspace_name="$2"
    local uuid="$3"
    local class="$4"
    local function_name="db_add_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    # Add entry to 'app_windows' table
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace '$workspace_name'" \
        -cmd ".param set :window '$window_name'" \
        -cmd ".param set :uuid '$uuid'" \
        -cmd ".param set :class '$class'" \
        "INSERT INTO app_windows (workspace_name, window_name, uuid, class, is_tab)
         VALUES (:workspace, :window, :uuid, :class, FALSE);"
    
    debug_log "$function_name: Added window '$window_name' (workspace: '$workspace_name', uuid: '$uuid', class: '$class')" "verbose"
}

db_delete_window() {
    local window_name="$1"
    local function_name="db_delete_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Delete entry from 'app_windows' table
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window '$window_name'" \
        "DELETE FROM app_windows WHERE window_name = :window;"
    
    debug_log "$function_name: Deleted window '$window_name'" "verbose"
}

db_claim_window() {
    local new_window_name="$1"
    local new_workspace_name="$2"
    local uuid="$3"
    local function_name="db_claim_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window '$new_window_name'" \
        -cmd ".param set :workspace '$new_workspace_name'" \
        -cmd ".param set :uuid '$uuid'" \
        "UPDATE app_windows 
         SET window_name = :window,
             workspace_name = :workspace
         WHERE uuid = :uuid;"
}

db_add_existing_windows() {
    local -n uuids_ref="$1"
    local -n classes_ref="$2"
    local window_name
    local workspace_name="~auto:workspace"
    local function_name="db_add_existing_windows"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    debug_array "$1" "verbose"
    debug_array "$2" "verbose"

    for i in "${!uuids_ref[@]}"; do
        window_name="~auto:${classes_ref[$i]}"

        sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :workspace '$workspace_name'" \
            -cmd ".param set :window '$window_name'" \
            -cmd ".param set :uuid '${uuids_ref[$i]}'" \
            -cmd ".param set :class '${classes_ref[$i]}'" \
            "INSERT OR IGNORE INTO app_windows (workspace_name, window_name, uuid, class, is_tab) 
             VALUES (:workspace, :window, :uuid, :class, FALSE);"
        
        # Check if row was inserted
        local changes
        changes=$(sqlite3 "$KDOITALL_DB" "SELECT changes()")
        
        if [ "$changes" -eq 1 ]; then
            debug_log "INSERTED: window_name='$window_name', uuid='${uuids_ref[$i]}', class='${classes_ref[$i]}'" "verbose"
        else
            debug_log "IGNORED: window_name='$window_name', uuid='${uuids_ref[$i]}' (already exists)" "verbose"
        fi
    done
}

db_delete_stale_windows() {
    local -n existing_uuids_ref="$1"
    local -n db_uuids_ref="$2"
    local -A existing_lookup=()
    local uuid_to_delete
    local function_name="db_delete_stale_windows"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    debug_array "$1" "verbose"
    debug_array "$2" "verbose"

    # Build lookup table for O(1) checking
    for uuid in "${existing_uuids_ref[@]}"; do
        existing_lookup["$uuid"]=1
    done
    
    debug_log "Built lookup table with ${#existing_lookup[@]} entries" "verbose"
    
    # Delete UUIDs that don't exist anymore
    for uuid_to_delete in "${db_uuids_ref[@]}"; do
        if [[ -z "${existing_lookup[$uuid_to_delete]}" ]]; then
            sqlite3 "$KDOITALL_DB" \
                -cmd ".param init" \
                -cmd ".param set :uuid '$uuid_to_delete'" \
                "DELETE FROM app_windows WHERE uuid = :uuid;"
            
            # Check if row was actually deleted
            local changes
            changes=$(sqlite3 "$KDOITALL_DB" "SELECT changes()")
            
            if [ "$changes" -eq 1 ]; then
                debug_log "DELETED: Stale window with uuid='$uuid_to_delete'" "verbose"
                echo "Deleted stale window: $uuid_to_delete"
            else
                debug_log "DELETE FAILED: uuid='$uuid_to_delete' not found in database" "verbose"
            fi
        else
            debug_log "KEPT: uuid='$uuid_to_delete' still exists" "verbose"
        fi
    done
}

