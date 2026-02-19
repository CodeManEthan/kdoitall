#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

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

    # Get all data in a single query
    db_query \
        "SELECT uuid, class, COALESCE(window_title, 'N/A') 
         FROM app_windows 
         WHERE uuid IS NOT NULL;"
    
    local uuid=""
    local class=""
    local window_title=""

    # Parse the pipe-separated output into arrays
    local row=""
    for row in "${DB_RESULT[@]}"; do
        IFS='|' read -r uuid class window_title <<< "$row"
        DB_UUIDS+=("$uuid")
        DB_CLASSES+=("$class")
        DB_TITLES+=("$window_title")
    done
    
    debug_log "$function_name" "Retrieved ${#DB_UUIDS[@]} tracked windows (UUIDs, classes, window titles)"
    debug_function_exit "$function_name"
    return 0
}

db_get_existing_window_uuids() {
    local function_name="db_get_existing_window_uuids"
    
    debug_function_enter "$function_name"
    
    # Reset global array
    DB_UUIDS=()
    
    # Populate global array from query
    db_query \
        "SELECT uuid FROM app_windows WHERE uuid IS NOT NULL;"
    DB_UUIDS=("${DB_RESULT[@]}")
    
    debug_log "$function_name" "Retrieved ${#DB_UUIDS[@]} tracked window UUIDs"
    debug_function_exit "$function_name"
    return 0
}

db_get_existing_window_classes() {
    local function_name="db_get_existing_window_classes"
    
    debug_function_enter "$function_name"
    
    # Reset global array
    DB_CLASSES=()
    
    # Populate global array from query
    db_query \
        "SELECT class FROM app_windows WHERE uuid IS NOT NULL;"
    DB_CLASSES=("${DB_RESULT[@]}")
    
    debug_log "$function_name" "Retrieved ${#DB_CLASSES[@]} tracked window classes"
    debug_function_exit "$function_name"
    return 0
}

db_get_existing_window_titles() {
    local function_name="db_get_existing_window_titles"
    
    debug_function_enter "$function_name"
    
    # Reset global array
    DB_TITLES=()
    
    # Populate global array from query
    db_query \
        "SELECT COALESCE(window_title, 'N/A') FROM app_windows WHERE uuid IS NOT NULL;"
    DB_TITLES=("${DB_RESULT[@]}")
    
    debug_log "$function_name" "Retrieved ${#DB_TITLES[@]} tracked window titles"
    debug_function_exit "$function_name"
    return 0
}

db_get_window_info_by_uuid() {
    local uuid="$1"
    local function_name="db_get_window_info_by_uuid"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    db_query \
        "SELECT class || '|' || COALESCE(window_title, 'N/A') 
         FROM app_windows WHERE uuid = :uuid;" \
        ":uuid" "$uuid"
    
    debug_log "$function_name" "Retrieved window info for UUID: $uuid"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && echo "${DB_RESULT[0]}"
    return 0
}

db_get_window_workspace() {
    local window_name="$1"
    local function_name="db_get_window_workspace"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    db_query \
        "SELECT workspace_name FROM app_windows WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    debug_log "$function_name" "Retrieved workspace for window: $window_name"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && echo "${DB_RESULT[0]}"
    return 0
}

db_list_tracked_windows() {
    local workspace_filter="${1:-}"
    local function_name="db_list_tracked_windows"

    debug_function_enter "$function_name" "$@"

    if [[ -n "$workspace_filter" ]]; then
        db_query \
            "SELECT window_name, workspace_name, class, COALESCE(window_title, 'N/A'), uuid
             FROM app_windows
             WHERE workspace_name = :workspace
             ORDER BY window_name;" \
            ":workspace" "$workspace_filter"
    else
        db_query \
            "SELECT window_name, workspace_name, class, COALESCE(window_title, 'N/A'), uuid
             FROM app_windows
             ORDER BY workspace_name, window_name;"
    fi

    debug_log "$function_name" "Listed tracked windows"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_active_workspace_windows() {
    local function_name="db_get_active_workspace_windows"

    debug_function_enter "$function_name"

    db_query \
        "SELECT
            aw.workspace_name,
            aw.window_name,
            aw.uuid,
            COALESCE(a.display_name, aw.class),
            COALESCE(aw.window_title, ''),
            COALESCE(wd.screen, ''),
            COALESCE(wd.position, '')
         FROM app_windows aw
         LEFT JOIN window_definitions wd ON aw.window_name = wd.window_name
         LEFT JOIN applications a ON wd.app_id = a.app_id
         INNER JOIN workspace_definitions ws ON aw.workspace_name = ws.workspace_name
         WHERE ws.is_active = TRUE
         ORDER BY aw.workspace_name, wd.display_order;"

    debug_log "$function_name" "Retrieved active workspace windows"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_untracked_windows() {
    local function_name="db_get_untracked_windows"

    debug_function_enter "$function_name"

    db_query \
        "SELECT
            aw.window_name,
            aw.uuid,
            aw.class,
            COALESCE(aw.window_title, '')
         FROM app_windows aw
         WHERE aw.workspace_name = '~auto:workspace'
         ORDER BY aw.class;"

    debug_log "$function_name" "Retrieved untracked windows"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_count_tracked_windows() {
    local function_name="db_count_tracked_windows"

    debug_function_enter "$function_name"

    db_query \
        "SELECT COUNT(*) FROM app_windows;"

    debug_log "$function_name" "Count: ${DB_RESULT[0]:-0}"
    debug_function_exit "$function_name"
    echo "${DB_RESULT[0]:-0}"
    return 0
}

db_dump_tracked_windows() {
    local function_name="db_dump_tracked_windows"

    debug_function_enter "$function_name"

    db_query \
        "SELECT workspace_name, window_name, uuid, class, is_tab FROM app_windows;"

    debug_log "$function_name" "Dumped ${#DB_RESULT[@]} rows"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}
