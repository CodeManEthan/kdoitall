#!/bin/bash

check_and_set_guard "_KDOITALL_DB_WINDOW_INFO_LOADED" || return 0

# ============================================================================
# Extended Window Information Database Functions
# ============================================================================
# These functions provide richer window data queries beyond basic tracking

# ----------------------------------------------------------------------------
# db_get_existing_window_uuids()
# Get all window UUIDs currently tracked in app_windows table
# Returns: Newline-separated list of UUIDs
# ----------------------------------------------------------------------------
db_get_existing_window_uuids() {
    local function_name="db_get_existing_window_uuids"
    local result=""
    
    debug_function_enter "$function_name"
    
    result=$(sqlite3 "$KDOITALL_DB" \
        "SELECT uuid FROM app_windows WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved tracked window UUIDs"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_get_existing_window_classes()
# Get all window classes currently tracked in app_windows table
# Returns: Newline-separated list of classes (in same order as UUIDs)
# ----------------------------------------------------------------------------
db_get_existing_window_classes() {
    local function_name="db_get_existing_window_classes"
    local result=""
    
    debug_function_enter "$function_name"
    
    result=$(sqlite3 "$KDOITALL_DB" \
        "SELECT class FROM app_windows WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved tracked window classes"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_get_existing_window_titles()
# Get all window titles currently tracked in app_windows table
# Returns: Newline-separated list of titles (in same order as UUIDs)
# ----------------------------------------------------------------------------
db_get_existing_window_titles() {
    local function_name="db_get_existing_window_titles"
    local result=""
    
    debug_function_enter "$function_name"
    
    result=$(sqlite3 "$KDOITALL_DB" \
        "SELECT COALESCE(window_title, 'N/A') FROM app_windows WHERE uuid IS NOT NULL;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved tracked window titles"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_get_window_info_by_uuid()
# Get class and title for a specific window UUID
# Returns: "class|title" format
# ----------------------------------------------------------------------------
db_get_window_info_by_uuid() {
    local uuid="$1"
    local function_name="db_get_window_info_by_uuid"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "uuid"
        debug_function_exit "$function_name"
        return 1
    fi
    
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
