#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_FIREFOX_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

# Load metadata from JSON into global variables
# This happens once when the file is sourced
_load_app_metadata() {
    local app_dir="${BASH_SOURCE[0]%/*}"
    local json_file="$app_dir/metadata.json"

    local metadata=""
    metadata=$(jq -r '[
        .terminal_command,
        .app_id,
        (.app_class // ""),
        .launch_mode,
        .launch_type
    ] | @tsv' "$json_file")

    # shellcheck disable=SC2034
    IFS=$'\t' read -r TERMINAL_COMMAND APP_ID APP_CLASS LAUNCH_MODE LAUNCH_TYPE <<< "$metadata"
}

_load_app_metadata

_launch_firefox() {
    local url="$1"

    firefox --new-window "$url" > /dev/null 2>&1 & disown
}

launch_firefox_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local url="$6"
    local window_title_pattern=""
    local function_name="launch_firefox_window"

    debug_function_enter "$function_name" "$@"

    window_title_pattern=" — Mozilla Firefox"

    execute_launch_window \
    "$workspace_name" "$window_name" "$APP_ID" "$desktop" "$screen" "$position" "$LAUNCH_MODE" "$LAUNCH_TYPE" "_launch_firefox" \
    "$APP_CLASS" "$window_title_pattern" "" "$url"

    debug_function_exit "$function_name"
}