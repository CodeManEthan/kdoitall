#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_CODE_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=lib/app-definitions/loader.sh
source "${LIB_DIR}/app-definitions/loader.sh"
# shellcheck source=lib/db/app.sh
source "${LIB_DIR}/db/app.sh"

load_app_metadata "${BASH_SOURCE[0]%/*}"

_launch_code() {
    local path="$1"

    code --new-window "$path" > /dev/null 2>&1 & disown
}

launch_code_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local directory_path="$6"
    
    local window_title_pattern=""
    local function_name="launch_code_window"

    debug_function_enter "$function_name" "$@"

    validate_directory_exists "$directory_path" || return 1

    local launch_properties=""
    launch_properties=$(db_get_app_launch_properties "$APP_ID")

    if [[ -z "$launch_properties" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $APP_ID"
        debug_function_exit "$function_name"
        return 1
    fi

    local class=""
    local launch_mode=""
    IFS='|' read -r class _ launch_mode _ <<< "$launch_properties"

    local directory=""
    directory=$(basename "$directory_path")
    window_title_pattern="$directory - Visual Studio Code"

    execute_launch_window \
    "$workspace_name" "$window_name" "$APP_ID" "$desktop" "$screen" "$position" "$launch_mode" "$LAUNCH_TYPE" "_launch_code" \
    "$class" "$window_title_pattern" "" "$directory_path"

    debug_function_exit "$function_name"
}

launch_code_workspace_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local workspace_path="$6"

    local window_title_pattern=""
    local function_name="launch_code_workspace_window"

    debug_function_enter "$function_name" "$@"

    validate_file_exists "$workspace_path" || return 1

    local launch_properties=""
    launch_properties=$(db_get_app_launch_properties "$APP_ID")

    if [[ -z "$launch_properties" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $APP_ID"
        debug_function_exit "$function_name"
        return 1
    fi

    local class=""
    local launch_mode=""
    IFS='|' read -r class _ launch_mode _ <<< "$launch_properties"

    local workspace=""
    workspace=$(basename "$workspace_path" .code-workspace)
    window_title_pattern="$workspace (Workspace) - Visual Studio Code"

    execute_launch_window \
    "$workspace_name" "$window_name" "$APP_ID" "$desktop" "$screen" "$position" "$launch_mode" "$LAUNCH_TYPE" "_launch_code" \
    "$class" "$window_title_pattern" "" "$workspace_path"

    debug_function_exit "$function_name"
}

