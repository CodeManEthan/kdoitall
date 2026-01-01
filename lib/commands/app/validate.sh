#!/bin/bash

# ============================================================================
# App Validate Command
# ============================================================================
# Validates all application files in lib/applications/

check_and_set_guard "_KDOITALL_APP_VALIDATE_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# app_validate()
# Validate all application definition files
# Parameters: none
# ----------------------------------------------------------------------------
app_validate() {
    local function_name="app_validate"
    
    debug_function_enter "$function_name" "$@"
    
    echo "Validating application definition files..."
    echo ""
    
    # Source the app-registry module (should already be loaded, but ensure it)
    if [[ ! -f "${LIB_DIR}/core/app-registry.sh" ]]; then
        echo "Error: app-registry.sh not found" >&2
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "app-registry.sh"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Call the registry validation function
    if registry_validate_all_app_files; then
        echo ""
        echo "✓ All application files are valid"
        debug_log "$function_name" "Validation completed successfully"
        debug_function_exit "$function_name"
        return 0
    else
        echo ""
        echo "✗ Some application files have validation errors"
        debug_error "$function_name" "$ERR_UNKNOWN" "registry_validate_all_app_files failed"
        debug_function_exit "$function_name"
        return 1
    fi
}
