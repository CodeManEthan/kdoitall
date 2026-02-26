#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_APP_REGISTRY_LOADED" || return 0

app_registry_exists() {
    local app_id="$1"
    local function_name="app_registry_exists"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    db_registry_query \
        "SELECT COUNT(*) FROM app_registry WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    if [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "App found in registry: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "App not in registry: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

app_registry_get_metadata() {
    local app_id="$1"
    local function_name="app_registry_get_metadata"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    db_registry_query \
        "SELECT app_id, app_name, app_class, window_title_pattern, launch_mode,
                supports_pid_validation, process_name
         FROM app_registry
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_log "$function_name" "No registry entry for: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Retrieved registry metadata for: $app_id"
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

app_registry_get_app_class() {
    local app_id="$1"
    local function_name="app_registry_get_app_class"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    db_registry_query \
        "SELECT app_class FROM app_registry WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    debug_log "$function_name" "Registry app_class for $app_id: ${DB_RESULT[0]:-NULL}"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && echo "${DB_RESULT[0]}"
    return 0
}

app_registry_list_apps() {
    local function_name="app_registry_list_apps"

    debug_function_enter "$function_name"

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    db_registry_query \
        "SELECT app_id, app_class, launch_mode FROM app_registry ORDER BY app_id;"

    debug_log "$function_name" "Listed all registry apps"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

app_registry_count_apps() {
    local function_name="app_registry_count_apps"

    debug_function_enter "$function_name"

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        echo "0"
        return 1
    fi

    db_registry_query \
        "SELECT COUNT(*) FROM app_registry;"

    debug_log "$function_name" "Registry app count: ${DB_RESULT[0]:-0}"
    debug_function_exit "$function_name"
    echo "${DB_RESULT[0]:-0}"
    return 0
}
