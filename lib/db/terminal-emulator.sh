#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_TERMINAL_EMULATOR_LOADED" || return 0

db_upsert_terminal_emulator() {
    local app_id="$1"
    local exec_flag="$2"
    local detection_source="${3:-auto}"
    local function_name="db_upsert_terminal_emulator"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$exec_flag" "exec_flag" || return 1

    db_query \
        "INSERT OR REPLACE INTO terminal_emulators (
            app_id, exec_flag, detection_source
        ) VALUES (
            :app_id, :exec_flag, :detection_source
        );" \
        ":app_id" "$app_id" \
        ":exec_flag" "$exec_flag" \
        ":detection_source" "$detection_source"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to upsert terminal emulator: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Upserted terminal emulator: $app_id (exec_flag=$exec_flag, source=$detection_source)"
    debug_function_exit "$function_name"
    return 0
}

db_is_terminal_emulator() {
    local app_id="$1"
    local function_name="db_is_terminal_emulator"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    db_query \
        "SELECT COUNT(*) FROM terminal_emulators WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to query terminal_emulators for $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ "${DB_RESULT[0]:-0}" -ge 1 ]]; then
        debug_log "$function_name" "App is terminal emulator: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "App is not terminal emulator: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_terminal_exec_flag() {
    local app_id="$1"
    local function_name="db_get_terminal_exec_flag"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    db_query \
        "SELECT exec_flag FROM terminal_emulators WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to query exec_flag for $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_log "$function_name" "No terminal emulator entry for: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "exec_flag for $app_id: ${DB_RESULT[0]}"
    debug_function_exit "$function_name"
    echo "${DB_RESULT[0]}"
    return 0
}

db_delete_terminal_emulator() {
    local app_id="$1"
    local function_name="db_delete_terminal_emulator"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    db_query \
        "DELETE FROM terminal_emulators WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    debug_log "$function_name" "Deleted terminal emulator entry for: $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_list_terminal_emulators() {
    local function_name="db_list_terminal_emulators"

    debug_function_enter "$function_name"

    db_query \
        "SELECT app_id, exec_flag, detection_source
         FROM terminal_emulators
         ORDER BY app_id;"

    debug_log "$function_name" "Listed all terminal emulators"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_set_terminal_exec_flag() {
    local app_id="$1"
    local exec_flag="$2"
    local function_name="db_set_terminal_exec_flag"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$exec_flag" "exec_flag" || return 1

    db_query \
        "UPDATE terminal_emulators SET exec_flag = :exec_flag WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":exec_flag" "$exec_flag"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to update exec_flag for: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Updated exec_flag for $app_id: $exec_flag"
    debug_function_exit "$function_name"
    return 0
}
