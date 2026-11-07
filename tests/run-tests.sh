#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Main test runner — executes all test files in numbered order

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helpers (sets up counters, assertion functions, and the throwaway
# data dir in KDOITALL_DATA_DIR)
source "$TESTS_DIR/test-helpers.sh"

# The data dir holds only this run's database and scripts
remove_test_data_dir() {
    if [[ -n "${KDOITALL_DATA_DIR:-}" && "$KDOITALL_DATA_DIR" == */kdoitall-test-data.* ]]; then
        rm -rf -- "$KDOITALL_DATA_DIR"
    fi
}
trap remove_test_data_dir EXIT

echo "================================================================"
echo "  kdoitall Test Suite"
echo "================================================================"
echo ""
echo "  Project:    $PROJECT_ROOT"
echo "  Data dir:   $KDOITALL_DATA_DIR (removed on exit)"
echo "  Database:   $DB_PATH"
echo "  Fixtures:   $FIXTURES_DIR"
echo ""

# Capture the terminal window so we can refocus it when tests finish
TERMINAL_UUID=$(kdotool getactivewindow 2>/dev/null) || TERMINAL_UUID=""

# ============================================================================
# Pre-clean: remove stale test data from previous runs
# ============================================================================

echo "Pre-cleaning stale test data..."
cleanup_test_workspaces
echo "Pre-clean complete."

# Snapshot live windows AFTER pre-clean so the baseline reflects the user's
# steady-state desktop without any test residue. Post-test orphan cleanup
# uses this baseline to avoid closing pre-existing user windows.
snapshot_baseline_windows

# ============================================================================
# Execute test files in order
# ============================================================================

# Collect test files
TEST_FILES=()
for f in "$TESTS_DIR"/test-[0-9]*.sh; do
    [[ -f "$f" ]] && TEST_FILES+=("$f")
done

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
    echo "No test files found!"
    exit 1
fi

echo ""
echo "Found ${#TEST_FILES[@]} test file(s):"
for f in "${TEST_FILES[@]}"; do
    echo "  $(basename "$f")"
done

# Track per-file pass state for gates
SUITE_EXIT_CODE=0

for test_file in "${TEST_FILES[@]}"; do
    test_basename="$(basename "$test_file")"

    # Run the test file in a subshell that inherits our functions/variables
    # but reports results back through the shared counters
    #
    # We source the file directly (not subshell) so that counters and gate
    # state are shared across files.
    source "$test_file" || true

    # Check if a critical gate failed — if so, skip remaining files
    if [[ "$CRITICAL_GATE_FAILED" == "true" ]]; then
        echo ""
        echo "!! Critical gate failed in $test_basename — skipping remaining test files"
        break
    fi
done

# ============================================================================
# Post-clean: ensure no orphaned test resources remain
# ============================================================================

echo ""
echo "Post-cleaning test resources..."
cleanup_all
# Safety net: close any windows of test-app classes that appeared during the
# run but weren't explicitly tracked. Protected by the pre-test baseline so
# the user's pre-existing windows are never touched.
cleanup_post_test_orphans
echo "Post-clean complete."

# ============================================================================
# Summary
# ============================================================================

# Refocus the terminal window so the user sees results immediately
if [[ -n "$TERMINAL_UUID" ]]; then
    kdotool windowactivate "$TERMINAL_UUID" 2>/dev/null || true
fi

if print_test_summary; then
    exit 0
else
    exit 1
fi
