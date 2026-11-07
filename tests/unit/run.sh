#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit test runner. Runs every tests/unit/test-*.sh in its own bash process.
#
# These tests load library code only: no KDE session, no KDE tools, no
# database, no windows. They are safe to run anywhere, and CI runs them.
# The integration suite (tests/run-tests.sh) is separate and needs a live
# Plasma session.

set -uo pipefail

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=()
count=0
for test_file in "$UNIT_DIR"/test-*.sh; do
    [[ -f "$test_file" ]] || continue
    count=$((count + 1))
    echo "$(basename "$test_file")"
    if ! bash "$test_file"; then
        failed+=("$(basename "$test_file")")
    fi
done

echo ""
if [[ "$count" -eq 0 ]]; then
    echo "No unit test files found."
    exit 1
fi
if [[ ${#failed[@]} -gt 0 ]]; then
    echo "Unit tests failed: ${failed[*]}"
    exit 1
fi
echo "All $count unit test files passed."
