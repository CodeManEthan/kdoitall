#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_APP_REGISTRY_LOADED" || return 0

app_registry_exists() {
    local app_id="$1"
    local function_name="app_registry_exists"
    local count=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    count=$(sqlite3 "$KDOITALL_REGISTRY_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COUNT(*) FROM app_registry WHERE app_id = :app_id;" 2>/dev/null)

    if [[ "$count" -eq 1 ]]; then
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
    local result=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    result=$(sqlite3 "$KDOITALL_REGISTRY_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_id, app_class, window_title_pattern, launch_mode,
                supports_pid_validation, process_name
         FROM app_registry
         WHERE app_id = :app_id;" 2>/dev/null)

    if [[ -z "$result" ]]; then
        debug_log "$function_name" "No registry entry for: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Retrieved registry metadata for: $app_id"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

app_registry_get_app_class() {
    local app_id="$1"
    local function_name="app_registry_get_app_class"
    local result=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    result=$(sqlite3 "$KDOITALL_REGISTRY_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_class FROM app_registry WHERE app_id = :app_id;" 2>/dev/null)

    debug_log "$function_name" "Registry app_class for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

app_registry_list_apps() {
    local function_name="app_registry_list_apps"
    local result=""

    debug_function_enter "$function_name"

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        return 1
    fi

    result=$(sqlite3 "$KDOITALL_REGISTRY_DB" \
        "SELECT app_id, app_class, launch_mode FROM app_registry ORDER BY app_id;" 2>/dev/null)

    debug_log "$function_name" "Listed all registry apps"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

app_registry_count_apps() {
    local function_name="app_registry_count_apps"
    local count=""

    debug_function_enter "$function_name"

    if [[ ! -f "$KDOITALL_REGISTRY_DB" ]]; then
        debug_log "$function_name" "Registry database not found: $KDOITALL_REGISTRY_DB"
        debug_function_exit "$function_name"
        echo "0"
        return 1
    fi

    count=$(sqlite3 "$KDOITALL_REGISTRY_DB" \
        "SELECT COUNT(*) FROM app_registry;" 2>/dev/null)

    debug_log "$function_name" "Registry app count: ${count:-0}"
    debug_function_exit "$function_name"
    echo "${count:-0}"
    return 0
}
