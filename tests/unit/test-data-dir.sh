#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: the data dir comes from one variable, and lib/db/bootstrap.sh
# makes a fresh, fully migrated database.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --- One variable --------------------------------------------------------------

assert_eq "data dir: database path derives from KDOITALL_DATA_DIR" \
    "$KDOITALL_DATA_DIR/kdoitall.db" "$KDOITALL_DB"
assert_eq "data dir: workspace scripts dir derives from KDOITALL_DATA_DIR" \
    "$KDOITALL_DATA_DIR/workspaces" "$WORKSPACE_SCRIPTS_DIR"

# --- Bootstrap -----------------------------------------------------------------

# shellcheck source=../../lib/db/bootstrap.sh
source "$LIB_DIR/db/bootstrap.sh"

if ! command -v sqlite3 &> /dev/null; then
    fail "bootstrap: sqlite3 is needed for these tests"
    finish
fi

quiet() { "$@" > /dev/null 2>&1; }

boot_db="$UNIT_TMP/boot/sub/kdoitall.db"
migrations_dir="$KDOITALL_ROOT/database/migrations"

assert_true "bootstrap: creates a new database" quiet \
    kdoitall_bootstrap_db "$boot_db" "$KDOITALL_ROOT/database/schema.sql" "$migrations_dir"
assert_true "bootstrap: database file exists" test -f "$boot_db"

migration_count=0
for f in "$migrations_dir"/[0-9]*.sql; do
    [[ -f "$f" ]] && migration_count=$((migration_count + 1))
done
assert_eq "bootstrap: every migration stamped as applied" \
    "$migration_count" "$(sqlite3 "$boot_db" 'SELECT COUNT(*) FROM schema_migrations;')"

sqlite3 "$boot_db" "CREATE TABLE unit_marker (x INTEGER);"
assert_true "bootstrap: leaves an existing database alone" quiet \
    kdoitall_bootstrap_db "$boot_db" "$KDOITALL_ROOT/database/schema.sql" "$migrations_dir"
assert_eq "bootstrap: existing tables kept" \
    "unit_marker" "$(sqlite3 "$boot_db" "SELECT name FROM sqlite_master WHERE name='unit_marker';")"

assert_false "bootstrap: missing schema file fails" quiet \
    kdoitall_bootstrap_db "$UNIT_TMP/other.db" "$UNIT_TMP/no-such-schema.sql" "$migrations_dir"

finish
