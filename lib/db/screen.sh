#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_SCREEN_LOADED" || return 0

db_set_screen_alias() {
    local alias="$1"
    local target="$2"
    local function_name="db_set_screen_alias"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$alias" "alias" || return 1
    validate_parameter_pass "$target" "target" || return 1

    db_query \
        "INSERT OR REPLACE INTO screen_aliases (alias, target)
         VALUES (:alias, :target);" \
        ":alias" "$alias" \
        ":target" "$target"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to set screen alias: $alias -> $target ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Set screen alias: $alias -> $target"
    debug_function_exit "$function_name"
    return 0
}

db_remove_screen_alias() {
    local alias="$1"
    local function_name="db_remove_screen_alias"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$alias" "alias" || return 1

    db_query \
        "DELETE FROM screen_aliases WHERE alias = :alias;" \
        ":alias" "$alias"

    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Removed screen alias: $alias"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Screen alias not found: $alias ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_screen_alias() {
    local alias="$1"
    local function_name="db_get_screen_alias"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$alias" "alias" || return 1

    db_query \
        "SELECT target FROM screen_aliases WHERE alias = :alias;" \
        ":alias" "$alias"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_log "$function_name" "Screen alias not found: $alias"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Resolved screen alias: $alias -> ${DB_RESULT[0]}"
    debug_function_exit "$function_name"
    echo "${DB_RESULT[0]}"
    return 0
}

db_list_screen_aliases() {
    local function_name="db_list_screen_aliases"

    debug_function_enter "$function_name"

    db_query \
        "SELECT alias, target FROM screen_aliases ORDER BY alias;"

    debug_log "$function_name" "Listed screen aliases"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_aliases_for_target() {
    local target="$1"
    local function_name="db_get_aliases_for_target"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$target" "target" || return 1

    db_query \
        "SELECT alias FROM screen_aliases WHERE target = :target ORDER BY alias;" \
        ":target" "$target"

    debug_log "$function_name" "Found aliases for target '$target'"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_all_screen_aliases() {
    local function_name="db_get_all_screen_aliases"

    debug_function_enter "$function_name"

    db_query \
        "SELECT target, alias FROM screen_aliases ORDER BY target, alias;"

    debug_log "$function_name" "Retrieved all screen aliases (${#DB_RESULT[@]} rows)"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}
