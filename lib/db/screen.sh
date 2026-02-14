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

    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :alias '$alias'" \
        -cmd ".param set :target '$target'" \
        "INSERT OR REPLACE INTO screen_aliases (alias, target)
         VALUES (:alias, :target);" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to set screen alias: $alias -> $target"
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
    local changes=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$alias" "alias" || return 1

    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :alias '$alias'" \
        "DELETE FROM screen_aliases WHERE alias = :alias;
         SELECT changes();" 2>/dev/null)

    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Removed screen alias: $alias"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Screen alias not found: $alias"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_screen_alias() {
    local alias="$1"
    local function_name="db_get_screen_alias"
    local result=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$alias" "alias" || return 1

    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :alias '$alias'" \
        "SELECT target FROM screen_aliases WHERE alias = :alias;" 2>/dev/null)

    if [[ -z "$result" ]]; then
        debug_log "$function_name" "Screen alias not found: $alias"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Resolved screen alias: $alias -> $result"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_list_screen_aliases() {
    local function_name="db_list_screen_aliases"
    local result=""

    debug_function_enter "$function_name"

    result=$(sqlite3 "$KDOITALL_DB" \
        "SELECT alias, target FROM screen_aliases ORDER BY alias;" 2>/dev/null)

    debug_log "$function_name" "Listed screen aliases"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_aliases_for_target() {
    local target="$1"
    local function_name="db_get_aliases_for_target"
    local result=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$target" "target" || return 1

    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :target '$target'" \
        "SELECT alias FROM screen_aliases WHERE target = :target ORDER BY alias;" 2>/dev/null)

    debug_log "$function_name" "Found aliases for target '$target': $result"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}
