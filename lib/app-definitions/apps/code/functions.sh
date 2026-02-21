#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_CODE_LOADED" || return 0

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

_launch_vscode() {
    local path="$1"

    code --new-window "$path" > /dev/null 2>&1 & disown
}

launch_vscode_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local directory_path="$6"
    
    local window_title_pattern=""
    local function_name="launch_vscode_window"

    debug_function_enter "$function_name" "$@"

    directory_path=$(safe_directory "$directory_path") || return 1

    local directory=""
    directory=$(basename "$directory_path")
    window_title_pattern="$directory - Visual Studio Code"
    window_title_pattern=$(safe_name "$window_title_pattern")

    execute_launch_window \
    "$workspace_name" "$window_name" "$APP_ID" "$desktop" "$screen" "$position" "$LAUNCH_MODE" "$LAUNCH_TYPE" "_launch_vscode" \
    "$APP_CLASS" "$window_title_pattern" "" "$directory_path"

    debug_function_exit "$function_name"
}

launch_vscode_workspace_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local workspace_path="$6"

    local window_title_pattern=""
    local function_name="launch_vscode_workspace_window"

    debug_function_enter "$function_name" "$@"

    workspace_path=$(safe_file "$workspace_path") || return 1

    local workspace=""
    workspace=$(basename "$workspace_path" .code-workspace)
    window_title_pattern="$workspace (Workspace) - Visual Studio Code"
    window_title_pattern=$(safe_name "$window_title_pattern")

    execute_launch_window \
    "$workspace_name" "$window_name" "$APP_ID" "$desktop" "$screen" "$position" "$LAUNCH_MODE" "$LAUNCH_TYPE" "_launch_vscode" \
    "$APP_CLASS" "$window_title_pattern" "" "$workspace_path"

    debug_function_exit "$function_name"
}

