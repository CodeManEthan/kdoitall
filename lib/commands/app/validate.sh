#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_VALIDATE_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../../app/registry.sh
source "${LIB_DIR}/app/registry.sh"

app_validate() {
    local function_name="app_validate"
    
    debug_function_enter "$function_name" "$@"
    
    print_info "Validating application definition files..."
    echo "" >&3
    
    # Call the registry validation function
    if registry_validate_all_app_files; then
        echo "" >&3
        print_success "All application files are valid"
        debug_log "$function_name" "Validation completed successfully"
        debug_function_exit "$function_name"
        return 0
    else
        echo "" >&3
        echo "✗ Some application files have validation errors" >&2
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_validate_all_app_files failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
