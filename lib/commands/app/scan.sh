#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_SCAN_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../../app/registry.sh
source "${LIB_DIR}/app/registry.sh"

app_scan() {
    local function_name="app_scan"
    
    debug_function_enter "$function_name" "$@"
    
    print_info "Scanning system for applications..."
    echo "" >&3
    
    # Call the registry scan function
    if registry_scan_applications; then
        echo "" >&3
        print_success "Application scan completed successfully"
        debug_log "$function_name" "Application scan completed"
        debug_function_exit "$function_name"
        return 0
    else
        echo "" >&3
        echo "✗ Application scan failed" >&2
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "registry_scan_applications failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
