#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_INFO_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

app_info() {
    local function_name="app_info"
    local app_id="$1"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        echo "Usage: kdoitall app info <app_id>" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Call the registry info function
    if display_application_info "$app_id"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "display_application_info failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
