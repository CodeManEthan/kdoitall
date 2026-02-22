#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_WINDOW_INFO_LOADED" || return 0

DB_UUIDS=()
DB_CLASSES=()
DB_TITLES=()

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

db_get_window_uuid_by_name() {
    local window_name="$1"
    local function_name="db_get_window_uuid_by_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    db_query \
        "SELECT uuid FROM app_windows WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    debug_log "$function_name" "UUID for '$window_name': ${DB_RESULT[0]:-<none>}"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 && -n "${DB_RESULT[0]}" ]] && echo "${DB_RESULT[0]}"
    return 0
}

db_get_workspace_windows_ordered() {
    local workspace_name="$1"
    local function_name="db_get_workspace_windows_ordered"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    db_query \
        "SELECT aw.window_name, aw.uuid
         FROM app_windows aw
         INNER JOIN window_definitions wd ON aw.window_name = wd.window_name
         WHERE aw.workspace_name = :workspace_name
         ORDER BY wd.display_order;" \
        ":workspace_name" "$workspace_name"

    debug_log "$function_name" "Retrieved ${#DB_RESULT[@]} ordered windows for workspace: $workspace_name"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_active_workspace_window_status() {
    local function_name="db_get_active_workspace_window_status"

    debug_function_enter "$function_name"

    # Start from window_definitions and LEFT JOIN app_windows
    # This shows all defined windows, marking which ones are currently alive
    # Sort: live windows first (is_alive DESC), then by display_order
    db_query \
        "SELECT
            wd.workspace_name,
            wd.window_name,
            COALESCE(aw.uuid, ''),
            COALESCE(a.display_name, aw.class, wd.app_id),
            COALESCE(aw.window_title, ''),
            COALESCE(wd.screen, ''),
            COALESCE(wd.position, ''),
            CASE WHEN aw.uuid IS NOT NULL THEN 1 ELSE 0 END AS is_alive
         FROM window_definitions wd
         INNER JOIN workspace_definitions ws ON wd.workspace_name = ws.workspace_name
         LEFT JOIN app_windows aw ON wd.window_name = aw.window_name
         LEFT JOIN applications a ON wd.app_id = a.app_id
         WHERE ws.is_active = TRUE
         ORDER BY wd.workspace_name, is_alive DESC, wd.display_order;"

    debug_log "$function_name" "Retrieved active workspace window status"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}
