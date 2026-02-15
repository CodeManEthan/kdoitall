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

    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :launch_function '$launch_function'" \
        -cmd ".param set :desktop '$desktop'" \
        -cmd ".param set :screen '$screen'" \
        -cmd ".param set :position '$position'" \
        -cmd ".param set :parameters '$parameters'" \
        -cmd ".param set :display_order '$display_order'" \
        "INSERT OR REPLACE INTO window_definitions (
            window_name, workspace_name, app_id, launch_function,
            desktop, screen, position, parameters, display_order
        ) VALUES (
            :window_name, :workspace_name, :app_id, :launch_function,
            :desktop, :screen, :position, :parameters, :display_order
        );" 2>/dev/null

    if [[ $? -ne 0 ]]; then
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
    local result=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        ".mode tabs
         SELECT window_name, workspace_name, app_id, launch_function,
                desktop, screen, position, COALESCE(parameters, ''), display_order
         FROM window_definitions
         WHERE window_name = :window_name;" 2>/dev/null)

    if [[ -z "$result" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_DEFINITION_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Retrieved window definition: $window_name"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_delete_window_definition() {
    local window_name="$1"
    local function_name="db_delete_window_definition"
    local changes=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        "DELETE FROM window_definitions WHERE window_name = :window_name;
         SELECT changes();" 2>/dev/null)

    if [[ "$changes" -eq 1 ]]; then
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

    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "DELETE FROM window_definitions WHERE workspace_name = :workspace_name;" 2>/dev/null

    debug_log "$function_name" "Deleted all window definitions for workspace: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}

db_list_window_definitions() {
    local workspace_name="${1:-}"
    local function_name="db_list_window_definitions"
    local result=""

    debug_function_enter "$function_name" "$@"

    if [[ -n "$workspace_name" ]]; then
        result=$(sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :workspace_name '$workspace_name'" \
            ".mode tabs
             SELECT window_name, workspace_name, app_id, launch_function,
                    desktop, screen, position, COALESCE(parameters, ''), display_order
             FROM window_definitions
             WHERE workspace_name = :workspace_name
             ORDER BY display_order;" 2>/dev/null)
    else
        result=$(sqlite3 "$KDOITALL_DB" \
            ".mode tabs
             SELECT window_name, workspace_name, app_id, launch_function,
                    desktop, screen, position, COALESCE(parameters, ''), display_order
             FROM window_definitions
             ORDER BY workspace_name, display_order;" 2>/dev/null)
    fi

    debug_log "$function_name" "Listed window definitions"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_window_definition_exists() {
    local window_name="$1"
    local function_name="db_window_definition_exists"
    local count=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        "SELECT COUNT(*) FROM window_definitions WHERE window_name = :window_name;" 2>/dev/null)

    if [[ "$count" -eq 1 ]]; then
        debug_log "$function_name" "Window definition exists: $window_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Window definition does not exist: $window_name"
        debug_function_exit "$function_name"
        return 1
    fi
}
