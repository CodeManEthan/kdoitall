#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: the shared terminal functions quote the paths they put in the
# command string they hand to "bash -c".
#
# The terminal is replaced by a function that saves the command string; the
# string is then run by bash with cd and source replaced by printers, so the
# test sees which path each one received.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=../../lib/core/core.sh
source "$LIB_DIR/core/core.sh"
# shellcheck source=../../lib/app-definitions/shared/terminal-emulator/functions.sh
source "$LIB_DIR/app-definitions/shared/terminal-emulator/functions.sh"

MARKER="$UNIT_TMP/marker"
SAVED="$UNIT_TMP/bash-command"

# Stubs for everything that would reach the DB or the desktop
_get_terminal_launch_context() { echo "konsole|multi|NULL|fake_terminal"; }
execute_launch_window() { "$9" ""; }
fake_terminal() {
    # Called as: fake_terminal bash -c <command>
    printf '%s' "$3" > "$SAVED"
}
# _launch_terminal_with_command backgrounds the terminal; wait for it
wait_for_saved() {
    local i=0
    while [[ ! -s "$SAVED" && $i -lt 50 ]]; do
        sleep 0.1
        i=$((i + 1))
    done
}

# Run a saved command string with cd and source printing their argument
run_saved() {
    local cmd=""
    cmd="$(cat "$SAVED")"
    bash -c '
        cd()     { printf "CD:%s\n" "$1"; }
        source() { printf "SOURCE:%s\n" "$1"; }
        exec()   { :; }
        eval "$1"
    ' _ "$cmd" < /dev/null
}

QUOTE_DIR="$UNIT_TMP/it's a \"dir\" \$(touch $MARKER)"
mkdir -p "$QUOTE_DIR"

# --- terminal_run_command_in_directory -----------------------------------------

: > "$SAVED"
terminal_run_command_in_directory ws win konsole 1 1 "$FULLSCREEN" "$QUOTE_DIR" "echo RAN" 2>/dev/null
wait_for_saved
assert_eq "run_command_in_directory: cd gets the exact path, command runs" \
    "CD:${QUOTE_DIR}"$'\n'"RAN" \
    "$(run_saved)"

# --- terminal_launch_dev_server -------------------------------------------------

VENV="$UNIT_TMP/venv 'x' \$(touch $MARKER)/bin/activate"
: > "$SAVED"
terminal_launch_dev_server ws win konsole 1 1 "$FULLSCREEN" "$QUOTE_DIR" "$VENV" "echo SERVER" 2>/dev/null
wait_for_saved
assert_eq "launch_dev_server: cd and source get the exact paths" \
    "CD:${QUOTE_DIR}"$'\n'"SOURCE:${VENV}"$'\n'"SERVER" \
    "$(run_saved)"

: > "$SAVED"
terminal_launch_dev_server ws win konsole 1 1 "$FULLSCREEN" "$QUOTE_DIR" "" "echo SERVER" 2>/dev/null
wait_for_saved
assert_eq "launch_dev_server: empty venv path skips the source" \
    "CD:${QUOTE_DIR}"$'\n'"SERVER" \
    "$(run_saved)"

# --- terminal_run_script --------------------------------------------------------

SCRIPT_PATH="$QUOTE_DIR/run me.sh"
printf '#!/bin/bash\necho "SCRIPT:$0"\n' > "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"
: > "$SAVED"
terminal_run_script ws win konsole 1 1 "$FULLSCREEN" "$SCRIPT_PATH" 2>/dev/null
wait_for_saved
assert_eq "run_script: the exact script path runs" \
    "SCRIPT:${SCRIPT_PATH}" \
    "$(run_saved)"

assert_false "terminal functions: no substitution ran (marker absent)" test -e "$MARKER"

finish
