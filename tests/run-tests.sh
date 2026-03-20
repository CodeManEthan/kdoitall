#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Main test runner — executes all test files in numbered order

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helpers (sets up counters, assertion functions, etc.)
source "$TESTS_DIR/test-helpers.sh"

echo "================================================================"
echo "  kdoitall Test Suite"
echo "================================================================"
echo ""
echo "  Project:    $PROJECT_ROOT"
echo "  Database:   $DB_PATH"
echo "  Fixtures:   $FIXTURES_DIR"
echo ""

# ============================================================================
# Pre-clean: remove stale test data from previous runs
# ============================================================================

echo "Pre-cleaning stale test data..."
cleanup_test_workspaces
echo "Pre-clean complete."

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
echo "Post-clean complete."

# ============================================================================
# Summary
# ============================================================================

if print_test_summary; then
    exit 0
else
    exit 1
fi
