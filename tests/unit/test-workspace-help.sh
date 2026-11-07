#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: `kdoitall workspace <subcommand> --help` (or -h) shows usage
# and never runs the subcommand, so "--help" is never taken as a workspace
# name.
#
# The subcommand files are not loaded: `source` is wrapped so a request for
# lib/commands/workspace/<file>.sh is recorded instead, and every handler is
# a stub that records that it ran. A subcommand passes when it printed its
# usage line and neither loaded its file nor ran its handler.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# shellcheck source=../../lib/commands/workspace/dispatcher.sh
source "$LIB_DIR/commands/workspace/dispatcher.sh"

ACTED_FILE="$UNIT_TMP/acted"
HELP_FILE="$UNIT_TMP/help"

source() {
    if [[ "$1" == "$LIB_DIR/commands/workspace/"* ]]; then
        echo "loaded $(basename "$1")" >> "$ACTED_FILE"
        return 0
    fi
    builtin source "$@"
}

for handler in workspace_create workspace_create_from_file workspace_list \
    workspace_info workspace_edit workspace_edit_noninteractive \
    workspace_open workspace_close workspace_focus workspace_minimize \
    workspace_delete workspace_export; do
    eval "$handler() { echo \"ran $handler\" >> \"\$ACTED_FILE\"; }"
done

# run_help <args...>: run workspace_command with fd 3 captured.
run_help() {
    : > "$ACTED_FILE"
    : > "$HELP_FILE"
    workspace_command "$@" 3> "$HELP_FILE" 2>/dev/null
}

# subcommand, alias, and the usage line's start in the workspace help
cases=(
    "create new create"
    "list ls list"
    "info i info"
    "edit e edit"
    "open o open"
    "close c close"
    "focus f focus"
    "minimize min minimize"
    "delete rm delete"
    "export exp export"
)

for entry in "${cases[@]}"; do
    read -r sub alias name <<< "$entry"
    for form in "$sub --help" "$alias -h" "$sub myspace --help" "$sub --help myspace"; do
        read -r -a words <<< "$form"
        run_help "${words[@]}"
        rc=$?
        assert_eq "workspace $form exits 0" "0" "$rc"
        assert_eq "workspace $form runs nothing" "" "$(cat "$ACTED_FILE")"
        assert_true "workspace $form shows the $name usage" \
            grep -q "^  $name (" "$HELP_FILE"
    done
done

run_help create myspace --from-file x.json --help
assert_eq "create --from-file ... --help runs nothing" "" "$(cat "$ACTED_FILE")"

run_help --help
rc=$?
assert_eq "workspace --help exits 0" "0" "$rc"
assert_true "workspace --help shows the full list" grep -q "^Workspace Subcommands:" "$HELP_FILE"

# Without --help the subcommand still runs
run_help delete myspace
assert_eq "workspace delete myspace still runs delete" \
    "loaded delete.sh ran workspace_delete" "$(tr '\n' ' ' < "$ACTED_FILE" | sed 's/ $//')"

finish
