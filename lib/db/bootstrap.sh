#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Create a fresh kdoitall database. Standalone on purpose: it needs only
# bash and sqlite3, and none of kdoitall's libraries, so install.sh,
# dev-reset.sh and the test suite can all source it.
#
#   kdoitall_bootstrap_db <db-file> <schema-file> <migrations-dir>
#
# Leaves an existing database alone. Otherwise creates the file's directory,
# loads the schema, and stamps every migration in <migrations-dir> as
# applied: schema.sql already includes what each migration does, so they
# are recorded, not run. Returns non-zero when the database can't be made.
kdoitall_bootstrap_db() {
    local db_file="$1"
    local schema_file="$2"
    local migrations_dir="$3"

    if [[ -f "$db_file" ]]; then
        echo "✓ Database already exists: $db_file"
        return 0
    fi

    if ! command -v sqlite3 &> /dev/null; then
        echo "⚠ sqlite3 not found — cannot initialize database: $db_file" >&2
        return 1
    fi

    if [[ ! -f "$schema_file" ]]; then
        echo "✗ Schema file not found: $schema_file" >&2
        return 1
    fi

    mkdir -p "$(dirname "$db_file")" || return 1

    if ! sqlite3 "$db_file" < "$schema_file"; then
        echo "✗ Failed to load schema into: $db_file" >&2
        return 1
    fi

    if [[ -d "$migrations_dir" ]]; then
        local migration_file="" migration_basename="" migration_version="" migration_name=""
        for migration_file in "$migrations_dir"/[0-9]*.sql; do
            [[ -f "$migration_file" ]] || continue
            migration_basename=$(basename "$migration_file")
            migration_version=$((10#${migration_basename%%_*}))
            migration_name="${migration_basename%.sql}"
            if ! sqlite3 "$db_file" \
                "INSERT OR IGNORE INTO schema_migrations (version, name) VALUES ($migration_version, '$migration_name');"; then
                echo "✗ Failed to record migration $migration_name in: $db_file" >&2
                return 1
            fi
        done
    fi

    echo "✓ Initialized database: $db_file"
    return 0
}
