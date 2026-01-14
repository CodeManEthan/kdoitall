#!/bin/bash

check_and_set_guard "_KDOITALL_DB_WINDOW_INFO_LOADED" || return 0

export -a DB_UUIDS=()
export -a DB_CLASSES=()
export -a DB_TITLES=()

db_get_all_windows() {
    local function_name="db_get_all_windows"
    
    debug_function_enter "$function_name"
    
    # Reset global arrays
    DB_UUIDS=()
    DB_CLASSES=()
    DB_TITLES=()
    
    # Get all data in a single query with tab-separated values
    # NOTE: .mode tabs forces tab-separated output
    local query_result=""
    query_result=$(sqlite3 "$KDOITALL_DB" \
        ".mode tabs" \
        "SELECT uuid, class, COALESCE(window_title, 'N/A') 
         FROM app_windows 
         WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    # Parse the tab-separated output into arrays
    while IFS=$'\t' read -r uuid class window_title; do
        DB_UUIDS+=("$uuid")
        DB_CLASSES+=("$class")
        DB_TITLES+=("$window_title")
    done <<< "$query_result"
    
    debug_log "$function_name" "Retrieved ${#DB_UUIDS[@]} tracked windows (UUIDs, classes, window titles)"
    debug_function_exit "$function_name"
    return 0
}

db_get_existing_window_uuids() {
    local function_name="db_get_existing_window_uuids"
    
    debug_function_enter "$function_name"
    
    # Reset global array
    DB_UUIDS=()
    
    # Populate global array directly from query
    mapfile -t DB_UUIDS < <(sqlite3 "$KDOITALL_DB" \
        "SELECT uuid FROM app_windows WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved ${#DB_UUIDS[@]} tracked window UUIDs"
    debug_function_exit "$function_name"
    return 0
}

db_get_existing_window_classes() {
    local function_name="db_get_existing_window_classes"
    
    debug_function_enter "$function_name"
    
    # Reset global array
    DB_CLASSES=()
    
    # Populate global array directly from query
    mapfile -t DB_CLASSES < <(sqlite3 "$KDOITALL_DB" \
        "SELECT class FROM app_windows WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved ${#DB_CLASSES[@]} tracked window classes"
    debug_function_exit "$function_name"
    return 0
}

db_get_existing_window_titles() {
    local function_name="db_get_existing_window_titles"
    
    debug_function_enter "$function_name"
    
    # Reset global array
    DB_TITLES=()
    
    # Populate global array directly from query
    mapfile -t DB_TITLES < <(sqlite3 "$KDOITALL_DB" \
        "SELECT COALESCE(window_title, 'N/A') FROM app_windows WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved ${#DB_TITLES[@]} tracked window titles"
    debug_function_exit "$function_name"
    return 0
}

db_get_window_info_by_uuid() {
    local uuid="$1"
    local function_name="db_get_window_info_by_uuid"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :uuid '$uuid'" \
        "SELECT class || '|' || COALESCE(window_title, 'N/A') 
         FROM app_windows WHERE uuid = :uuid;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved window info for UUID: $uuid"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}
