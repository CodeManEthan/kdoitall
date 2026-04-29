#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_MIGRATIONS_LOADED" || return 0

# shellcheck source=../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"

# Apply any pending schema migrations to the main database.
#
# Runs once at startup, before db_server_start, so it can shell out to
# sqlite3 directly without contending with the Python coproc for the
# database file. Migrations are forward-only and tracked in the
# schema_migrations table.
db_run_migrations() {
    local function_name="db_run_migrations"
    local migrations_dir="${KDOITALL_ROOT}/database/migrations"

    debug_function_enter "$function_name"

    if [[ ! -d "$migrations_dir" ]]; then
        debug_log "$function_name" "No migrations directory at $migrations_dir"
        debug_function_exit "$function_name"
        return 0
    fi

    # If the DB doesn't exist yet, the install hasn't been run. Don't try to
    # initialize from migrations alone — let downstream code surface the
    # missing-DB error so the user is directed to run install.sh.
    if [[ ! -f "$KDOITALL_DB" ]]; then
        debug_log "$function_name" "Database file not present at $KDOITALL_DB; skipping migrations"
        debug_function_exit "$function_name"
        return 0
    fi

    # Ensure the tracking table exists. Covers DBs created before the
    # migration system was added.
    local sql_output=""
    if ! sql_output=$(sqlite3 "$KDOITALL_DB" "CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );" 2>&1); then
        print_error "Failed to create schema_migrations tracking table"
        [[ -n "$sql_output" ]] && print_error "  $sql_output"
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Cannot create schema_migrations: $sql_output"
        debug_function_exit "$function_name"
        return 1
    fi

    local applied_versions=()
    local row=""
    while IFS= read -r row; do
        [[ -n "$row" ]] && applied_versions+=("$row")
    done < <(sqlite3 "$KDOITALL_DB" "SELECT version FROM schema_migrations;" 2>/dev/null)

    local migration_file=""
    local applied_count=0
    for migration_file in "$migrations_dir"/[0-9]*.sql; do
        [[ -f "$migration_file" ]] || continue

        local file_basename=""
        file_basename="$(basename "$migration_file")"
        local version="${file_basename%%_*}"
        # Force decimal interpretation so leading zeros don't become octal
        version=$((10#$version))
        local migration_name="${file_basename%.sql}"

        local found=0
        local v=""
        for v in "${applied_versions[@]}"; do
            if [[ "$v" == "$version" ]]; then
                found=1
                break
            fi
        done
        [[ $found -eq 1 ]] && continue

        if ! sql_output=$(sqlite3 "$KDOITALL_DB" < "$migration_file" 2>&1); then
            print_error "Failed to apply migration: $file_basename"
            [[ -n "$sql_output" ]] && print_error "  $sql_output"
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Migration failed: $file_basename ($sql_output)"
            debug_function_exit "$function_name"
            return 1
        fi

        if ! sql_output=$(sqlite3 "$KDOITALL_DB" \
            "INSERT INTO schema_migrations (version, name) VALUES ($version, '$migration_name');" \
            2>&1); then
            print_error "Migration applied but failed to record: $file_basename"
            [[ -n "$sql_output" ]] && print_error "  $sql_output"
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to record migration: $file_basename"
            debug_function_exit "$function_name"
            return 1
        fi

        print_info "Applied database migration: $file_basename"
        applied_count=$((applied_count + 1))
    done

    if [[ $applied_count -gt 0 ]]; then
        debug_log "$function_name" "Applied $applied_count migration(s)"
    fi

    debug_function_exit "$function_name"
    return 0
}
