#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: the workspace script generator.
#
# Every value stored for a window must reach its launch function as exactly
# that string, as one argument, and nothing in it may run while the script
# is sourced. Crafted identifiers must be refused before any DB lookup.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=../../lib/db/helpers.sh
source "$LIB_DIR/db/helpers.sh"
# shellcheck source=../../lib/workspace/generator.sh
source "$LIB_DIR/workspace/generator.sh"

MARKER="$UNIT_TMP/marker"
CALLS="$UNIT_TMP/calls"
DB_CALLS="$UNIT_TMP/db-calls"
SCRIPT="$UNIT_TMP/ws.sh"
: > "$DB_CALLS"

# A per-app definition directory whose path needs quoting
APP_DIR="$UNIT_TMP/app dir's \$(touch $MARKER)"
mkdir -p "$APP_DIR"
echo '# per-app functions (empty for the test)' > "$APP_DIR/functions.sh"

# The one DB call the generator makes, stubbed and counted
db_get_app_directory_path() {
    echo "$1" >> "$DB_CALLS"
    echo "$APP_DIR"
}

# Launch-function stubs: record each call's arguments, one call per line
record_call() {
    local line=""
    printf -v line '%q ' "$@"
    printf '%s\n' "$line" >> "$CALLS"
}
launch_by_app_id()                  { record_call launch_by_app_id "$@"; }
terminal_launch_dev_server()        { record_call terminal_launch_dev_server "$@"; }
terminal_run_command_in_directory() { record_call terminal_run_command_in_directory "$@"; }
vscode_open_project()               { record_call vscode_open_project "$@"; }

expected_call() {
    local line=""
    printf -v line '%q ' "$@"
    printf '%s\n' "$line"
}

# --- Values with shell syntax reach the functions unchanged ---------------------

dir_value="/srv/my \"app\" \`id\` \$(touch $MARKER) 'x'"
cmd_value="echo \"\$(touch $MARKER)\" && \`touch $MARKER\`"
dev_params="${dir_value}"$'\t\t'"${cmd_value}"
run_params=$'\t'"ls -la"
perapp_params="first"$'\t'"second \$(touch $MARKER)"

WORKSPACE_APPS=(
    "org.kde.kate|w-one|launch_by_app_id|1|2|FULLSCREEN|"
    "konsole|w-two|terminal_launch_dev_server|2|1|LEFTHALF|${dev_params}"
    "konsole|w-three|terminal_run_command_in_directory|1|1|TOPLEFT|${run_params}"
    "code|w-four|vscode_open_project|3|1|RIGHTHALF|${perapp_params}"
    "code|w-five|vscode_open_project|3|1|RIGHTHALF|"
)

if generate_workspace_script "unit-ws" "$SCRIPT" 2>/dev/null; then
    pass "generator: script written"
else
    fail "generator: script written"
fi

assert_true "generator: script passes bash -n" bash -n "$SCRIPT"

# Source it as bin/kdoitall would, with the launch functions stubbed. The
# guards stop the script's source lines from replacing the stubs.
_KDOITALL_CORE_LOADED=1
_KDOITALL_SHARED_TERMINAL_EMULATOR_LOADED=1
: > "$CALLS"
# shellcheck source=/dev/null
source "$SCRIPT"
open_workspace_unit_ws

mapfile -t got < "$CALLS"
assert_eq "generator: five launch calls" "5" "${#got[@]}"

assert_eq "launch_by_app_id: exact arguments" \
    "$(expected_call launch_by_app_id unit-ws w-one org.kde.kate 1 2 "$FULLSCREEN")" \
    "${got[0]:-}"

assert_eq "terminal function: quotes, substitutions and empty middle field kept" \
    "$(expected_call terminal_launch_dev_server unit-ws w-two konsole 2 1 "$LEFTHALF" "$dir_value" "" "$cmd_value")" \
    "${got[1]:-}"

assert_eq "terminal function: leading empty field kept" \
    "$(expected_call terminal_run_command_in_directory unit-ws w-three konsole 1 1 "$TOPLEFT" "" "ls -la")" \
    "${got[2]:-}"

assert_eq "per-app function: tab inside the one params string kept" \
    "$(expected_call vscode_open_project unit-ws w-four 3 1 "$RIGHTHALF" "$perapp_params")" \
    "${got[3]:-}"

assert_eq "per-app function: empty params is one empty argument" \
    "$(expected_call vscode_open_project unit-ws w-five 3 1 "$RIGHTHALF" "")" \
    "${got[4]:-}"

assert_false "generator: no substitution ran (marker absent)" test -e "$MARKER"

# --- Crafted identifiers and values are refused before any DB call ---------------

refused() {
    local label="$1"
    shift
    WORKSPACE_APPS=("$@")
    rm -f -- "$SCRIPT"
    : > "$DB_CALLS"
    if generate_workspace_script "unit-ws" "$SCRIPT" 2>/dev/null; then
        fail "$label: refused"
    else
        pass "$label: refused"
    fi
    assert_false "$label: no script written" test -e "$SCRIPT"
    assert_eq "$label: no DB call" "" "$(cat "$DB_CALLS")"
}

refused "crafted launch function" \
    "code|w-six|\$(touch $MARKER)\\|terminal_run_script|1|1|FULLSCREEN|"
refused "crafted position" \
    "org.kde.kate|w-six|launch_by_app_id|1|1|FULLSCREEN\"; touch $MARKER; \"|"
refused "crafted window name" \
    "org.kde.kate|w\$(touch $MARKER)|launch_by_app_id|1|1|FULLSCREEN|"
refused "crafted app id" \
    "org.kde.kate;touch|w-six|launch_by_app_id|1|1|FULLSCREEN|"
refused "'|' in params" \
    "konsole|w-six|terminal_run_script|1|1|FULLSCREEN|/a|b"
refused "newline in params" \
    "konsole|w-six|terminal_run_script|1|1|FULLSCREEN|/a"$'\n'"touch $MARKER"

# shellcheck disable=SC2034  # read by generate_workspace_script
WORKSPACE_APPS=("org.kde.kate|w-one|launch_by_app_id|1|1|FULLSCREEN|")
rm -f -- "$SCRIPT"
if generate_workspace_script "bad\$(touch $MARKER)" "$SCRIPT" 2>/dev/null; then
    fail "crafted workspace name: refused"
else
    pass "crafted workspace name: refused"
fi
assert_false "crafted workspace name: no script written" test -e "$SCRIPT"

assert_false "refusals: no substitution ran (marker absent)" test -e "$MARKER"

finish
