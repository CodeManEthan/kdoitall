#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_WINDOW_DEFINITIONS_LOADED" || return 0

db_add_window_definition() {
    local window_name="$1"
    local workspace_name="$2"
    local app_id="$3"
    local launch_function="$4"
    local desktop="$5"
    local screen="$6"
    local position="$7"
    local parameters="${8:-}"
    local display_order="${9:-0}"
    local function_name="db_add_window_definition"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$launch_function" "launch_function" || return 1
    validate_parameter_pass "$desktop" "desktop" || return 1
    validate_parameter_pass "$screen" "screen" || return 1
    validate_parameter_pass "$position" "position" || return 1

    db_query \
        "INSERT OR REPLACE INTO window_definitions (
            window_name, workspace_name, app_id, launch_function,
            desktop, screen, position, parameters, display_order
        ) VALUES (
            :window_name, :workspace_name, :app_id, :launch_function,
            :desktop, :screen, :position, :parameters, :display_order
        );" \
        ":window_name" "$window_name" \
        ":workspace_name" "$workspace_name" \
        ":app_id" "$app_id" \
        ":launch_function" "$launch_function" \
        ":desktop" "$desktop" \
        ":screen" "$screen" \
        ":position" "$position" \
        ":parameters" "$parameters" \
        ":display_order" "$display_order"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add window definition: $window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Added window definition: $window_name (workspace: $workspace_name, app: $app_id)"
    debug_function_exit "$function_name"
    return 0
}

db_get_window_definition() {
    local window_name="$1"
    local function_name="db_get_window_definition"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    db_query \
        "SELECT window_name, workspace_name, app_id, launch_function,
                desktop, screen, position, COALESCE(parameters, ''), display_order
         FROM window_definitions
         WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_WINDOW_DEFINITION_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Retrieved window definition: $window_name"
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_delete_window_definition() {
    local window_name="$1"
    local function_name="db_delete_window_definition"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    db_query \
        "DELETE FROM window_definitions WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Deleted window definition: $window_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_WINDOW_DEFINITION_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_delete_window_definitions_for_workspace() {
    local workspace_name="$1"
    local function_name="db_delete_window_definitions_for_workspace"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    db_query \
        "DELETE FROM window_definitions WHERE workspace_name = :workspace_name;" \
        ":workspace_name" "$workspace_name"

    debug_log "$function_name" "Deleted all window definitions for workspace: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}

db_list_window_definitions() {
    local workspace_name="${1:-}"
    local function_name="db_list_window_definitions"

    debug_function_enter "$function_name" "$@"

    if [[ -n "$workspace_name" ]]; then
        db_query \
            "SELECT window_name, workspace_name, app_id, launch_function,
                    desktop, screen, position, COALESCE(parameters, ''), display_order
             FROM window_definitions
             WHERE workspace_name = :workspace_name
             ORDER BY display_order;" \
            ":workspace_name" "$workspace_name"
    else
        db_query \
            "SELECT window_name, workspace_name, app_id, launch_function,
                    desktop, screen, position, COALESCE(parameters, ''), display_order
             FROM window_definitions
             ORDER BY workspace_name, display_order;"
    fi

    debug_log "$function_name" "Listed window definitions"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_window_definition_exists() {
    local window_name="$1"
    local function_name="db_window_definition_exists"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    db_query \
        "SELECT COUNT(*) FROM window_definitions WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Window definition exists: $window_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Window definition does not exist: $window_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_workspace_app_ids() {
    local workspace_name="$1"
    local function_name="db_get_workspace_app_ids"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    db_query \
        "SELECT DISTINCT app_id
         FROM window_definitions
         WHERE workspace_name = :workspace_name
         ORDER BY app_id;" \
        ":workspace_name" "$workspace_name"

    debug_log "$function_name" "Retrieved app IDs for workspace: $workspace_name"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}
