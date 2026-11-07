#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Shared setup and assertions for the unit tests in tests/unit/.
#
# Unit tests load library code only. They need no KDE session, no kdotool,
# no kscreen-doctor and no database, and they never run bin/kdoitall. Each
# test file is run in its own bash process by tests/unit/run.sh.

set -uo pipefail

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$UNIT_DIR/../.." && pwd)"

# Everything a test writes goes under one temp dir, removed on exit. HOME and
# the XDG dirs point into it so nothing reaches the real user's files.
UNIT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/kdoitall-unit.XXXXXX")"
trap 'rm -rf -- "$UNIT_TMP"' EXIT

export HOME="$UNIT_TMP/home"
export XDG_DATA_HOME="$UNIT_TMP/data"
export XDG_CONFIG_HOME="$UNIT_TMP/config"
export XDG_STATE_HOME="$UNIT_TMP/state"
export KDOITALL_DATA_DIR="$UNIT_TMP/data/kdoitall"
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$KDOITALL_DATA_DIR"

export LIB_DIR="$PROJECT_ROOT/lib"
export KDOITALL_ROOT="$PROJECT_ROOT"

# fd 3 carries kdoitall's user-facing display output
exec 3>/dev/null

UNIT_PASSED=0
UNIT_FAILED=0

# Load the same first two layers bin/kdoitall loads, without the user config.
# This runs at the top level, not in a function: some of these files declare
# arrays with plain "declare", which inside a function would make them local.
# shellcheck source=../../lib/core/error-codes.sh
source "$LIB_DIR/core/error-codes.sh"
# shellcheck source=../../lib/utils/debug.sh
source "$LIB_DIR/utils/debug.sh"
# shellcheck source=../../config
source "$KDOITALL_ROOT/config"
# shellcheck source=../../lib/core/common.sh
source "$LIB_DIR/core/common.sh"
# shellcheck source=../../lib/utils/positions.sh
source "$LIB_DIR/utils/positions.sh"
# shellcheck source=../../lib/utils/checks.sh
source "$LIB_DIR/utils/checks.sh"
# shellcheck source=../../lib/utils/validators.sh
source "$LIB_DIR/utils/validators.sh"

pass() {
    ((UNIT_PASSED++)) || true
    printf '  PASS  %s\n' "$1"
}

fail() {
    ((UNIT_FAILED++)) || true
    printf '  FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '        %s\n' "$2"
    fi
}

# assert_eq <label> <expected> <actual>
assert_eq() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1" "expected: $(printf '%q' "$2")  got: $(printf '%q' "$3")"
    fi
}

# assert_true <label> <command...>
assert_true() {
    local label="$1"
    shift
    if "$@"; then
        pass "$label"
    else
        fail "$label" "command failed: $*"
    fi
}

# assert_false <label> <command...>
assert_false() {
    local label="$1"
    shift
    if "$@"; then
        fail "$label" "command succeeded: $*"
    else
        pass "$label"
    fi
}

# Print the counts and exit non-zero when anything failed.
finish() {
    printf '  %d passed, %d failed\n' "$UNIT_PASSED" "$UNIT_FAILED"
    [[ "$UNIT_FAILED" -eq 0 ]]
    exit
}
