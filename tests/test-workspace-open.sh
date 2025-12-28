#!/bin/bash

check_and_set_guard "_KDOITALL_TEST_OPEN_LOADED" || return 0

# shellcheck source=lib/applications/firefox.sh
source "${LIB_DIR}/applications/firefox.sh"
# shellcheck source=lib/applications/vscode.sh
source "${LIB_DIR}/applications/vscode.sh"

debug_log "Starting Test Script (Open)"

launch_vscode_window "finance-tracker-vscode" "1" "1" "$FULLSCREEN_POSITION" "/home/jpluto/projects/finance_tracker"
