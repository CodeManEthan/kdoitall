#!/bin/bash
# Phase 3 validation tests for db-server.py
# Tests: edge-case values, server lifecycle, error propagation, connection reuse

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_SCRIPT="${PROJECT_DIR}/lib/db/db-server.py"
TEST_DB="/tmp/kdoitall-test-$$.db"
TEST_DB2="/tmp/kdoitall-test-registry-$$.db"

PASS_COUNT=0
FAIL_COUNT=0

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# --- Server lifecycle ---
_SERVER_IN=""
_SERVER_OUT=""
_SERVER_PID=""

server_start() {
    coproc DB_SERVER { python3 "$SERVER_SCRIPT"; }
    _SERVER_IN="${DB_SERVER[1]}"
    _SERVER_OUT="${DB_SERVER[0]}"
    _SERVER_PID="$DB_SERVER_PID"
}

server_stop() {
    if [[ -n "$_SERVER_PID" ]]; then
        # $_SERVER_IN holds a file descriptor number, so >& writes stdout to that
        # descriptor; shellcheck reads it as a stdout+stderr redirect to a file.
        # shellcheck disable=SC2261
        printf '%s\n' "QUIT" >&"$_SERVER_IN" 2>/dev/null
        wait "$_SERVER_PID" 2>/dev/null
        _SERVER_PID=""
    fi
}

# --- Query helper (mirrors lib/db/helpers.sh) ---
DB_STATUS=""
DB_RESULT=()
DB_ERROR=""

send_query() {
    local db_path="$1"
    local query="$2"
    shift 2

    local param_count=""
    param_count=$(( $# / 2 ))

    printf '%s\n%s\n%s\n' "$db_path" "$query" "$param_count" \
        >&"$_SERVER_IN"

    while [[ $# -ge 2 ]]; do
        printf '%s\n%s\n' "${1#:}" "$2" >&"$_SERVER_IN"
        shift 2
    done

    printf '%s\n' "---" >&"$_SERVER_IN"

    DB_RESULT=()
    DB_ERROR=""
    local line=""

    read -r DB_STATUS <&"$_SERVER_OUT"

    while read -r line <&"$_SERVER_OUT"; do
        [[ "$line" == "---" ]] && break
        DB_RESULT+=("$line")
    done

    if [[ "$DB_STATUS" == "ERR" ]]; then
        DB_ERROR="${DB_RESULT[0]:-unknown error}"
        return 1
    fi

    return 0
}

# --- Test assertions ---
assert_ok() {
    local test_name="$1"
    if [[ "$DB_STATUS" == "OK" ]]; then
        ((PASS_COUNT++)) || true
        echo -e "  ${GREEN}PASS${RESET} $test_name"
    else
        ((FAIL_COUNT++)) || true
        echo -e "  ${RED}FAIL${RESET} $test_name — expected OK, got $DB_STATUS: $DB_ERROR"
    fi
}

assert_err() {
    local test_name="$1"
    if [[ "$DB_STATUS" == "ERR" ]]; then
        ((PASS_COUNT++)) || true
        echo -e "  ${GREEN}PASS${RESET} $test_name"
    else
        ((FAIL_COUNT++)) || true
        echo -e "  ${RED}FAIL${RESET} $test_name — expected ERR, got $DB_STATUS"
    fi
}

assert_result() {
    local test_name="$1"
    local expected="$2"
    local actual="${DB_RESULT[0]:-}"
    if [[ "$actual" == "$expected" ]]; then
        ((PASS_COUNT++)) || true
        echo -e "  ${GREEN}PASS${RESET} $test_name"
    else
        ((FAIL_COUNT++)) || true
        echo -e "  ${RED}FAIL${RESET} $test_name — expected '$expected', got '$actual'"
    fi
}

assert_count() {
    local test_name="$1"
    local expected="$2"
    local actual="${#DB_RESULT[@]}"
    if [[ "$actual" -eq "$expected" ]]; then
        ((PASS_COUNT++)) || true
        echo -e "  ${GREEN}PASS${RESET} $test_name"
    else
        ((FAIL_COUNT++)) || true
        echo -e "  ${RED}FAIL${RESET} $test_name — expected $expected rows, got $actual"
    fi
}

# --- Cleanup ---
cleanup() {
    server_stop
    rm -f "$TEST_DB" "$TEST_DB2"
}
trap cleanup EXIT

# ================================================================
# TEST SUITE
# ================================================================

echo -e "${YELLOW}=== Phase 3: db-server.py Validation ===${RESET}"
echo ""

# --- Start server ---
server_start

# --- Setup: create test table ---
echo -e "${YELLOW}[Setup] Creating test table${RESET}"
send_query "$TEST_DB" \
    "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, value TEXT);"
assert_ok "Create table"

# ================================================================
echo ""
echo -e "${YELLOW}[1] Edge-case values${RESET}"
# ================================================================

# Single quotes (the original vulnerability)
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (1, :name, :value);" \
    ":name" "Kate's Editor" ":value" "It's a test"
assert_ok "Single quotes in values"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 1;"
assert_result "Read back single-quote value" "Kate's Editor"

# Double quotes
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (2, :name, :value);" \
    ":name" 'She said "hello"' ":value" "double\"quotes"
assert_ok "Double quotes in values"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 2;"
assert_result "Read back double-quote value" 'She said "hello"'

# Semicolons (SQL injection attempt)
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (3, :name, :value);" \
    ":name" "drop; DROP TABLE test;--" ":value" "injection attempt"
assert_ok "Semicolons in values"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 3;"
assert_result "Read back semicolon value" "drop; DROP TABLE test;--"

# Verify table still exists after injection attempt
send_query "$TEST_DB" \
    "SELECT COUNT(*) FROM test;"
assert_ok "Table survived injection attempt"

# Parentheses and backticks
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (4, :name, :value);" \
    ":name" "GNOME Files (Nautilus)" ":value" '`backtick`'
assert_ok "Parentheses and backticks"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 4;"
assert_result "Read back parentheses value" "GNOME Files (Nautilus)"

# Dollar signs and backslashes
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (5, :name, :value);" \
    ":name" '$HOME/path' ":value" 'back\\slash'
assert_ok "Dollar signs and backslashes"

# SQL keywords as values
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (6, :name, :value);" \
    ":name" "SELECT * FROM users" ":value" "WHERE 1=1; DROP TABLE test"
assert_ok "SQL keywords as values"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 6;"
assert_result "Read back SQL keyword value" "SELECT * FROM users"

# Unicode: em-dash, smart quotes, CJK
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (7, :name, :value);" \
    ":name" "What's New — Firefox" ":value" "日本語テスト"
assert_ok "Unicode characters (em-dash, CJK)"

send_query "$TEST_DB" \
    "SELECT value FROM test WHERE id = 7;"
assert_result "Read back unicode value" "日本語テスト"

# Empty string
send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (8, :name, :value);" \
    ":name" "" ":value" "has empty name"
assert_ok "Empty string parameter"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 8;"
assert_result "Read back empty string" ""

# Pipe character in values (known limitation — check behavior)
send_query "$TEST_DB" \
    "INSERT INTO test (id, name) VALUES (9, :name);" \
    ":name" "col1|col2"
assert_ok "Pipe in single-column value"

send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 9;"
assert_result "Read back pipe value (single column)" "col1|col2"

# ================================================================
echo ""
echo -e "${YELLOW}[2] Error propagation${RESET}"
# ================================================================

# Bad SQL syntax
send_query "$TEST_DB" \
    "SELECTT * FROMM test;" || true
assert_err "Bad SQL syntax returns ERR"

# Nonexistent table
send_query "$TEST_DB" \
    "SELECT * FROM nonexistent_table;" || true
assert_err "Nonexistent table returns ERR"

# Constraint violation (duplicate primary key)
send_query "$TEST_DB" \
    "INSERT INTO test (id, name) VALUES (1, :name);" \
    ":name" "duplicate" || true
# This should fail due to UNIQUE constraint on id
if [[ "$DB_STATUS" == "ERR" ]]; then
    ((PASS_COUNT++)) || true
    echo -e "  ${GREEN}PASS${RESET} Constraint violation returns ERR"
else
    ((FAIL_COUNT++)) || true
    echo -e "  ${RED}FAIL${RESET} Constraint violation — expected ERR, got $DB_STATUS"
fi

# Server should still be alive after errors
send_query "$TEST_DB" \
    "SELECT COUNT(*) FROM test;"
assert_ok "Server alive after errors"

# ================================================================
echo ""
echo -e "${YELLOW}[3] Connection reuse across databases${RESET}"
# ================================================================

# Create second database
send_query "$TEST_DB2" \
    "CREATE TABLE registry (app_id TEXT PRIMARY KEY, app_class TEXT);"
assert_ok "Create table in second database"

send_query "$TEST_DB2" \
    "INSERT INTO registry (app_id, app_class) VALUES (:id, :class);" \
    ":id" "firefox" ":class" "firefox"
assert_ok "Insert into second database"

# Query first database — should still work (connection reuse)
send_query "$TEST_DB" \
    "SELECT COUNT(*) FROM test;"
assert_ok "First database still accessible"

# Query second database
send_query "$TEST_DB2" \
    "SELECT app_class FROM registry WHERE app_id = :id;" \
    ":id" "firefox"
assert_result "Read from second database" "firefox"

# Interleave queries between databases
send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 1;"
assert_result "Interleaved: read from DB1" "Kate's Editor"

send_query "$TEST_DB2" \
    "SELECT app_id FROM registry WHERE app_class = :class;" \
    ":class" "firefox"
assert_result "Interleaved: read from DB2" "firefox"

# ================================================================
echo ""
echo -e "${YELLOW}[4] Multi-row output${RESET}"
# ================================================================

send_query "$TEST_DB" \
    "SELECT id, name FROM test ORDER BY id;"
assert_ok "Multi-row SELECT"

local_count="${#DB_RESULT[@]}"
if [[ "$local_count" -ge 8 ]]; then
    ((PASS_COUNT++)) || true
    echo -e "  ${GREEN}PASS${RESET} Got $local_count rows (expected >= 8)"
else
    ((FAIL_COUNT++)) || true
    echo -e "  ${RED}FAIL${RESET} Expected >= 8 rows, got $local_count"
fi

# Verify pipe-delimited format
first_row="${DB_RESULT[0]}"
if [[ "$first_row" == *"|"* ]]; then
    ((PASS_COUNT++)) || true
    echo -e "  ${GREEN}PASS${RESET} Rows are pipe-delimited: $first_row"
else
    ((FAIL_COUNT++)) || true
    echo -e "  ${RED}FAIL${RESET} Expected pipe-delimited row, got: $first_row"
fi

# Parameterless query returning zero rows
send_query "$TEST_DB" \
    "SELECT id FROM test WHERE id = 999;"
assert_ok "Zero-row SELECT returns OK"
assert_count "Zero-row SELECT has 0 results" 0

# ================================================================
echo ""
echo -e "${YELLOW}[5] Server lifecycle — stop and restart${RESET}"
# ================================================================

server_stop

# Verify PID is cleared
if [[ -z "$_SERVER_PID" ]]; then
    ((PASS_COUNT++)) || true
    echo -e "  ${GREEN}PASS${RESET} Server PID cleared after stop"
else
    ((FAIL_COUNT++)) || true
    echo -e "  ${RED}FAIL${RESET} Server PID not cleared: $_SERVER_PID"
fi

# Restart
server_start

# Should work immediately after restart
send_query "$TEST_DB" \
    "SELECT name FROM test WHERE id = 1;"
assert_result "Query works after restart" "Kate's Editor"

send_query "$TEST_DB2" \
    "SELECT app_id FROM registry WHERE app_class = :class;" \
    ":class" "firefox"
assert_result "Second DB works after restart" "firefox"

# ================================================================
echo ""
echo -e "${YELLOW}[6] NULL handling${RESET}"
# ================================================================

send_query "$TEST_DB" \
    "INSERT INTO test (id, name, value) VALUES (10, :name, NULL);" \
    ":name" "null-value-test"
assert_ok "Insert with SQL NULL"

send_query "$TEST_DB" \
    "SELECT value FROM test WHERE id = 10;"
# NULL becomes empty string in pipe output
assert_result "NULL renders as empty string" ""

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${YELLOW}==============================${RESET}"
total=""
total=$((PASS_COUNT + FAIL_COUNT))
echo -e "  Total: $total  ${GREEN}Pass: $PASS_COUNT${RESET}  ${RED}Fail: $FAIL_COUNT${RESET}"
echo -e "${YELLOW}==============================${RESET}"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
