#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_LIST_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

app_list() {
    local function_name="app_list"
    local filter="${1:-all}"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate filter parameter
    case "$filter" in
        all|terminal|desktop)
            debug_log "$function_name" "Listing applications with filter: $filter"
            ;;
        *)
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid filter: $filter"
            echo "Valid filters: all, terminal, desktop" >&2
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # Call the registry list function
    if display_applications_list "$filter"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_list_applications failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
