#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_HELPERS_LOADED" || return 0

# --- Server lifecycle ---

_DB_SERVER_IN=""
_DB_SERVER_OUT=""
_DB_SERVER_PID=""

db_server_start() {
    coproc DB_SERVER { python3 "${LIB_DIR}/db/db-server.py"; }
    _DB_SERVER_IN="${DB_SERVER[1]}"
    _DB_SERVER_OUT="${DB_SERVER[0]}"
    _DB_SERVER_PID="$DB_SERVER_PID"
}

db_server_stop() {
    if [[ -n "$_DB_SERVER_PID" ]]; then
        printf '%s\n' "QUIT" >&"$_DB_SERVER_IN" 2>/dev/null
        wait "$_DB_SERVER_PID" 2>/dev/null
        _DB_SERVER_PID=""
    fi
}

# --- Query interface ---

# Globals set by db_query after each call
DB_STATUS=""   # "OK" or "ERR"
DB_RESULT=()   # Array of pipe-delimited result rows
DB_ERROR=""    # Error message (when DB_STATUS is "ERR")

# Execute a parameterized query against the main database.
# Usage: db_query "SQL with :params" [":key" "value" ...]
db_query() {
    local query="$1"
    shift
    # Collapse multiline SQL to single line for line-based protocol
    query="${query//$'\n'/ }"

    local param_count=""
    param_count=$(( $# / 2 ))

    printf '%s\n%s\n%s\n' "$KDOITALL_DB" "$query" "$param_count" \
        >&"$_DB_SERVER_IN"

    while [[ $# -ge 2 ]]; do
        printf '%s\n%s\n' "${1#:}" "$2" >&"$_DB_SERVER_IN"
        shift 2
    done

    printf '%s\n' "---" >&"$_DB_SERVER_IN"

    DB_RESULT=()
    DB_ERROR=""
    local line=""

    read -r DB_STATUS <&"$_DB_SERVER_OUT"

    while read -r line <&"$_DB_SERVER_OUT"; do
        [[ "$line" == "---" ]] && break
        DB_RESULT+=("$line")
    done

    if [[ "$DB_STATUS" == "ERR" ]]; then
        DB_ERROR="${DB_RESULT[0]:-unknown error}"
        return 1
    fi

    return 0
}

# Execute a parameterized query against the app registry database.
# Usage: db_registry_query "SQL with :params" [":key" "value" ...]
db_registry_query() {
    local query="$1"
    shift
    # Collapse multiline SQL to single line for line-based protocol
    query="${query//$'\n'/ }"

    local param_count=""
    param_count=$(( $# / 2 ))

    printf '%s\n%s\n%s\n' "$KDOITALL_REGISTRY_DB" "$query" "$param_count" \
        >&"$_DB_SERVER_IN"

    while [[ $# -ge 2 ]]; do
        printf '%s\n%s\n' "${1#:}" "$2" >&"$_DB_SERVER_IN"
        shift 2
    done

    printf '%s\n' "---" >&"$_DB_SERVER_IN"

    DB_RESULT=()
    DB_ERROR=""
    local line=""

    read -r DB_STATUS <&"$_DB_SERVER_OUT"

    while read -r line <&"$_DB_SERVER_OUT"; do
        [[ "$line" == "---" ]] && break
        DB_RESULT+=("$line")
    done

    if [[ "$DB_STATUS" == "ERR" ]]; then
        DB_ERROR="${DB_RESULT[0]:-unknown error}"
        return 1
    fi

    return 0
}
