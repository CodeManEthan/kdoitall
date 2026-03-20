#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test helper functions for the automated test suite

# ============================================================================
# Configuration
# ============================================================================

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
KDOITALL="$PROJECT_ROOT/bin/kdoitall"
FIXTURES_DIR="$TESTS_DIR/fixtures"
DB_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"
WORKSPACE_SCRIPTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/workspaces"

# Position tolerance in pixels for geometry comparisons
POSITION_TOLERANCE=10

# Command output (set by run_kdoitall / run_kdoitall_raw)
CMD_OUTPUT=""
CMD_EXIT_CODE=0

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_TEST=""
CRITICAL_GATE_FAILED=false

# Track test-opened windows for cleanup
declare -a TEST_WINDOW_UUIDS=()

# ============================================================================
# Lifecycle
# ============================================================================

test_start() {
    CURRENT_TEST="$1"
    printf "  %-60s " "$CURRENT_TEST"
}

test_pass() {
    local label="${1:-$CURRENT_TEST}"
    ((TESTS_PASSED++)) || true
    echo "PASS"
}

test_fail() {
    local reason="${1:-}"
    ((TESTS_FAILED++)) || true
    echo "FAIL"
    if [[ -n "$reason" ]]; then
        echo "    -> $reason"
    fi
}

test_skip() {
    local reason="${1:-}"
    ((TESTS_SKIPPED++)) || true
    echo "SKIP"
    if [[ -n "$reason" ]]; then
        echo "    -> $reason"
    fi
}

# Mark a critical gate as failed — downstream test files should check this
gate_failed() {
    CRITICAL_GATE_FAILED=true
}

check_gate() {
    if [[ "$CRITICAL_GATE_FAILED" == "true" ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# Command Execution
# ============================================================================

# Run kdoitall with --info flag, capture stdout+fd3 and exit code.
# Sets: CMD_OUTPUT, CMD_EXIT_CODE
run_kdoitall() {
    CMD_OUTPUT=""
    CMD_EXIT_CODE=0
    CMD_OUTPUT=$(eval "$KDOITALL --info $*" 2>&1) || CMD_EXIT_CODE=$?
}

# Run kdoitall without --info (for commands that shouldn't use it, like --help)
run_kdoitall_raw() {
    CMD_OUTPUT=""
    CMD_EXIT_CODE=0
    CMD_OUTPUT=$(eval "$KDOITALL $*" 2>&1) || CMD_EXIT_CODE=$?
}

# ============================================================================
# Assertions — Exit Code
# ============================================================================

assert_exit_code() {
    local expected="$1"
    local label="${2:-$CURRENT_TEST}"

    if [[ "$CMD_EXIT_CODE" -eq "$expected" ]]; then
        return 0
    else
        test_fail "Expected exit code $expected, got $CMD_EXIT_CODE"
        return 1
    fi
}

assert_success() {
    local label="${1:-$CURRENT_TEST}"
    assert_exit_code 0 "$label"
}

assert_failure() {
    local label="${1:-$CURRENT_TEST}"
    if [[ "$CMD_EXIT_CODE" -ne 0 ]]; then
        return 0
    else
        test_fail "Expected non-zero exit code, got 0"
        return 1
    fi
}

# ============================================================================
# Assertions — Output
# ============================================================================

assert_output_contains() {
    local substring="$1"
    local label="${2:-$CURRENT_TEST}"

    if [[ "$CMD_OUTPUT" == *"$substring"* ]]; then
        return 0
    else
        test_fail "Output does not contain '$substring'"
        return 1
    fi
}

assert_output_not_contains() {
    local substring="$1"
    local label="${2:-$CURRENT_TEST}"

    if [[ "$CMD_OUTPUT" != *"$substring"* ]]; then
        return 0
    else
        test_fail "Output unexpectedly contains '$substring'"
        return 1
    fi
}

assert_output_not_empty() {
    local label="${1:-$CURRENT_TEST}"
    if [[ -n "$CMD_OUTPUT" ]]; then
        return 0
    else
        test_fail "Output is empty"
        return 1
    fi
}

# ============================================================================
# Assertions — Database
# ============================================================================

# Run a raw sqlite3 query and return the result
db_test_query() {
    local sql="$1"
    sqlite3 "$DB_PATH" "$sql" 2>/dev/null
}

assert_db_row_exists() {
    local table="$1"
    local where_clause="$2"
    local label="${3:-$CURRENT_TEST}"
    local count=""

    count=$(db_test_query "SELECT COUNT(*) FROM $table WHERE $where_clause;")
    if [[ "$count" -gt 0 ]]; then
        return 0
    else
        test_fail "No row in $table WHERE $where_clause"
        return 1
    fi
}

assert_db_row_not_exists() {
    local table="$1"
    local where_clause="$2"
    local label="${3:-$CURRENT_TEST}"
    local count=""

    count=$(db_test_query "SELECT COUNT(*) FROM $table WHERE $where_clause;")
    if [[ "$count" -eq 0 ]]; then
        return 0
    else
        test_fail "Unexpected row in $table WHERE $where_clause (count=$count)"
        return 1
    fi
}

assert_db_value() {
    local sql="$1"
    local expected="$2"
    local label="${3:-$CURRENT_TEST}"
    local actual=""

    actual=$(db_test_query "$sql")
    if [[ "$actual" == "$expected" ]]; then
        return 0
    else
        test_fail "DB value mismatch: expected '$expected', got '$actual'"
        return 1
    fi
}

# ============================================================================
# Assertions — File System
# ============================================================================

assert_file_exists() {
    local path="$1"
    local label="${2:-$CURRENT_TEST}"

    if [[ -f "$path" ]]; then
        return 0
    else
        test_fail "File does not exist: $path"
        return 1
    fi
}

assert_file_not_exists() {
    local path="$1"
    local label="${2:-$CURRENT_TEST}"

    if [[ ! -f "$path" ]]; then
        return 0
    else
        test_fail "File unexpectedly exists: $path"
        return 1
    fi
}

# ============================================================================
# Assertions — Window Verification (live window state via kdotool)
# ============================================================================

assert_window_exists() {
    local uuid="$1"
    local label="${2:-$CURRENT_TEST}"

    if kdotool getwindowname "$uuid" &>/dev/null; then
        return 0
    else
        test_fail "Window UUID $uuid does not exist"
        return 1
    fi
}

assert_window_not_exists() {
    local uuid="$1"
    local label="${2:-$CURRENT_TEST}"

    if ! kdotool getwindowname "$uuid" &>/dev/null; then
        return 0
    else
        test_fail "Window UUID $uuid unexpectedly exists"
        return 1
    fi
}

assert_window_on_desktop() {
    local uuid="$1"
    local expected_desktop="$2"
    local label="${3:-$CURRENT_TEST}"
    local actual_desktop=""

    actual_desktop=$(kdotool get_desktop_for_window "$uuid" 2>/dev/null) || {
        test_fail "Cannot get desktop for UUID $uuid"
        return 1
    }

    if [[ "$actual_desktop" -eq "$expected_desktop" ]]; then
        return 0
    else
        test_fail "Window on desktop $actual_desktop, expected $expected_desktop"
        return 1
    fi
}

assert_window_geometry_approx() {
    # Verify window position and size are within tolerance
    local uuid="$1"
    local expected_x="$2"
    local expected_y="$3"
    local expected_w="$4"
    local expected_h="$5"
    local label="${6:-$CURRENT_TEST}"

    local geom=""
    geom=$(kdotool getwindowgeometry "$uuid" 2>/dev/null) || {
        test_fail "Cannot get geometry for UUID $uuid"
        return 1
    }

    # Parse kdotool output:
    #   Window {uuid}
    #   Position: X,Y
    #   Geometry: WxH
    local actual_x actual_y actual_w actual_h
    actual_x=$(echo "$geom" | grep -oP 'Position:\s*\K-?[0-9]+(?=,)')
    actual_y=$(echo "$geom" | grep -oP 'Position:\s*-?[0-9]+,\K-?[0-9]+')
    actual_w=$(echo "$geom" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
    actual_h=$(echo "$geom" | grep -oP 'Geometry:\s*[0-9]+x\K[0-9]+')

    local ok=true
    local details=""

    if (( (actual_x - expected_x) > POSITION_TOLERANCE || (expected_x - actual_x) > POSITION_TOLERANCE )); then
        ok=false
        details+=" x=$actual_x(exp $expected_x)"
    fi
    if (( (actual_y - expected_y) > POSITION_TOLERANCE || (expected_y - actual_y) > POSITION_TOLERANCE )); then
        ok=false
        details+=" y=$actual_y(exp $expected_y)"
    fi
    if (( (actual_w - expected_w) > POSITION_TOLERANCE || (expected_w - actual_w) > POSITION_TOLERANCE )); then
        ok=false
        details+=" w=$actual_w(exp $expected_w)"
    fi
    if (( (actual_h - expected_h) > POSITION_TOLERANCE || (expected_h - actual_h) > POSITION_TOLERANCE )); then
        ok=false
        details+=" h=$actual_h(exp $expected_h)"
    fi

    if [[ "$ok" == "true" ]]; then
        return 0
    else
        test_fail "Geometry mismatch (tolerance=${POSITION_TOLERANCE}px):$details"
        return 1
    fi
}

assert_active_window() {
    local expected_uuid="$1"
    local label="${2:-$CURRENT_TEST}"
    local actual_uuid=""

    actual_uuid=$(kdotool getactivewindow 2>/dev/null) || {
        test_fail "Cannot get active window"
        return 1
    }

    if [[ "$actual_uuid" == "$expected_uuid" ]]; then
        return 0
    else
        test_fail "Active window is $actual_uuid, expected $expected_uuid"
        return 1
    fi
}

# ============================================================================
# Window UUID Helpers
# ============================================================================

# Get UUID for a tracked window by name from the database
get_test_window_uuid() {
    local window_name="$1"
    db_test_query "SELECT uuid FROM app_windows WHERE window_name='$window_name';"
}

# Get screen geometry from kscreen-doctor for assertions
# Returns: x_origin y_origin width height (space-separated)
get_screen_geometry() {
    local output_num="$1"
    # Query the kdoitall database for cached screen info
    # The screen info is stored in runtime globals, but for tests we query kscreen-doctor
    # For simplicity, we use kdoitall's own screen list output
    local screen_info=""
    screen_info=$($KDOITALL --info screen list 2>&1)
    # This is approximate; tests that need exact geometry will use the DB
    echo "$screen_info"
}

# ============================================================================
# Cleanup Utilities
# ============================================================================

# Remove all test-* workspaces from database and close their windows
cleanup_test_workspaces() {
    echo "Cleaning up test workspaces..."

    # Get test workspace names
    local workspaces=""
    workspaces=$(db_test_query "SELECT workspace_name FROM workspace_definitions WHERE workspace_name LIKE 'test-%';")

    if [[ -z "$workspaces" ]]; then
        return 0
    fi

    # Close any active test workspaces (best effort)
    while IFS= read -r ws_name; do
        [[ -z "$ws_name" ]] && continue
        local is_active=""
        is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='$ws_name';")
        if [[ "$is_active" == "1" ]]; then
            # Get window UUIDs and close them
            local uuids=""
            uuids=$(db_test_query "SELECT aw.uuid FROM app_windows aw JOIN window_definitions wd ON aw.window_name=wd.window_name WHERE wd.workspace_name='$ws_name';")
            while IFS= read -r uuid; do
                [[ -z "$uuid" ]] && continue
                kdotool windowclose "$uuid" 2>/dev/null || true
            done <<< "$uuids"
        fi

        # Delete from database
        db_test_query "DELETE FROM app_windows WHERE window_name IN (SELECT window_name FROM window_definitions WHERE workspace_name='$ws_name');"
        db_test_query "DELETE FROM window_definitions WHERE workspace_name='$ws_name';"
        db_test_query "DELETE FROM workspace_definitions WHERE workspace_name='$ws_name';"

        # Delete script file
        rm -f "$WORKSPACE_SCRIPTS_DIR/${ws_name}.sh"
    done <<< "$workspaces"
}

# Close windows tracked during tests
cleanup_test_windows() {
    for uuid in "${TEST_WINDOW_UUIDS[@]}"; do
        kdotool windowclose "$uuid" 2>/dev/null || true
    done
    TEST_WINDOW_UUIDS=()
}

# Track a window UUID for cleanup
track_test_window() {
    local uuid="$1"
    TEST_WINDOW_UUIDS+=("$uuid")
}

# Full cleanup: windows then workspace data
cleanup_all() {
    cleanup_test_windows
    cleanup_test_workspaces
}

# ============================================================================
# Summary
# ============================================================================

print_section_header() {
    local title="$1"
    echo ""
    echo "================================================================"
    echo "  $title"
    echo "================================================================"
}

print_test_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo ""
    echo "================================================================"
    echo "  TEST SUMMARY"
    echo "================================================================"
    echo "  Total:   $total"
    echo "  Passed:  $TESTS_PASSED"
    echo "  Failed:  $TESTS_FAILED"
    echo "  Skipped: $TESTS_SKIPPED"
    echo "================================================================"

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# Retry helper for window state assertions (handles timing)
# ============================================================================

# Retry a command up to N times with a delay between attempts
# Usage: retry <max_attempts> <delay_seconds> <command...>
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2

    local attempt=1
    while (( attempt <= max_attempts )); do
        if "$@"; then
            return 0
        fi
        if (( attempt < max_attempts )); then
            sleep "$delay"
        fi
        ((attempt++))
    done
    return 1
}
