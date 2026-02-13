#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_OPTIONS_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

app_options() {
    local function_name="app_options"
    local app_id="$1"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        echo "Usage: kdoitall app options <app_id>" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Call the registry launch options function
    if display_launch_options "$app_id"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_get_launch_options failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
