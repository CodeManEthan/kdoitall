#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_LOADER_LOADED" || return 0

# shellcheck source=json-parser.sh
source "${LIB_DIR}/app-definitions/json-parser.sh"

load_app_metadata() {
    local app_dir="$1"
    local function_name="load_app_metadata"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_dir" "app_dir" || return 1
    validate_directory_exists "$app_dir" || return 1

    local json_file="${app_dir}/metadata.json"

    validate_file_exists "$json_file" || return 1

    APP_ID=$(basename "$app_dir")

    TERMINAL_COMMAND=""
    TERMINAL_COMMAND=$(json_get_terminal_command "$json_file")

    if [[ -z "$TERMINAL_COMMAND" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "terminal_command not found in $json_file"
        debug_function_exit "$function_name"
        return 1
    fi

    # shellcheck disable=SC2034
    LAUNCH_TYPE="$LAUNCH_TYPE_TERMINAL"

    debug_log "$function_name" "Loaded metadata for $APP_ID: command=$TERMINAL_COMMAND"
    debug_function_exit "$function_name"
    return 0
}
