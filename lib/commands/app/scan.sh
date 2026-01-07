#!/bin/bash

check_and_set_guard "_KDOITALL_APP_SCAN_COMMAND_LOADED" || return 0

# shellcheck source=../../app/registry.sh
source "${LIB_DIR}/app/registry.sh"

app_scan() {
    local function_name="app_scan"
    
    debug_function_enter "$function_name" "$@"
    
    echo "Scanning system for applications..."
    echo ""
    
    # Call the registry scan function
    if registry_scan_applications; then
        echo ""
        echo "✓ Application scan completed successfully"
        debug_log "$function_name" "Application scan completed"
        debug_function_exit "$function_name"
        return 0
    else
        echo ""
        echo "✗ Application scan failed"
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_scan_applications failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
