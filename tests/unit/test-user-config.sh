#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Unit tests: the user config, sourced after the project config, can
# replace DESKTOP_FILE_LOCATIONS.

# shellcheck source=helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

mkdir -p "$(dirname "$KDOITALL_CONFIG")"
cat > "$KDOITALL_CONFIG" << 'CONF'
DESKTOP_FILE_LOCATIONS=(
    "/usr/share/applications"
    "/srv/apps"
)
CONF

# Source in a subshell, as bin/kdoitall does after the project config.
# A readonly array would make this fail with "readonly variable".
override_output="$( (
    # shellcheck source=/dev/null
    source "$KDOITALL_CONFIG" && printf '%s\n' "${DESKTOP_FILE_LOCATIONS[@]}"
) 2>&1)"
override_status=$?

assert_eq "user config: setting DESKTOP_FILE_LOCATIONS succeeds" "0" "$override_status"
assert_eq "user config: DESKTOP_FILE_LOCATIONS takes the user's dirs" \
    "$(printf '%s\n' /usr/share/applications /srv/apps)" "$override_output"

finish
