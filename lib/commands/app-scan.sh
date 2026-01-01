#!/bin/bash

# ============================================================================
# App Scan Command
# ============================================================================
# Scans the system for available applications and populates the registry

check_and_set_guard "_KDOITALL_APP_SCAN_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# app_scan()
# Scan system for applications and populate the registry
# Parameters: none
# ----------------------------------------------------------------------------
app_scan() {
    local function_name="app_scan"
    
    debug_function_enter "$function_name" "$@"
    
    echo "Scanning system for applications..."
    echo ""
    
    # Source the app-registry module (should already be loaded, but ensure it)
    if [[ ! -f "${LIB_DIR}/core/app-registry.sh" ]]; then
        echo "Error: app-registry.sh not found" >&2
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "app-registry.sh"
        debug_function_exit "$function_name"
        return 1
    fi
    
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
