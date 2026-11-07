#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: every $ERR_* name the code uses is defined in
# lib/core/error-codes.sh and has a message in ERROR_MESSAGES.
#
# The scripts run under set -u, so an undefined ERR_* name crashes the
# caller with "unbound variable", and debug_error crashes the same way on a
# code that has no ERROR_MESSAGES entry. Both only show up on an error path,
# which is the path least often run by hand.
#
# Defined names come from the sourced file itself (compgen), not from a text
# match. Used names are every $ERR_X or ${ERR_X} in bin/kdoitall, lib/ and
# scripts/.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

declare -A defined=()
while IFS= read -r name; do
    defined["$name"]=1
done < <(compgen -v ERR_)

assert_true "error-codes.sh defines ERR_* names" test "${#defined[@]}" -gt 0

used_names=()
mapfile -t used_names < <(
    grep -rhoE '\$\{?ERR_[A-Z0-9_]+' \
        "$PROJECT_ROOT/bin/kdoitall" "$PROJECT_ROOT/lib" "$PROJECT_ROOT/scripts" \
        | sed -E 's/^\$\{?//' | sort -u
)

assert_true "the code uses ERR_* names" test "${#used_names[@]}" -gt 0

undefined=()
no_message=()
for name in "${used_names[@]}"; do
    if [[ -z "${defined[$name]:-}" ]]; then
        undefined+=("$name")
        continue
    fi
    if [[ -z "${ERROR_MESSAGES[${!name}]:-}" ]]; then
        no_message+=("$name")
    fi
done

assert_eq "every used ERR_* name is defined" "" "${undefined[*]}"
assert_eq "every used ERR_* code has a message" "" "${no_message[*]}"

finish
