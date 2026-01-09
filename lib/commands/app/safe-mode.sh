#!/bin/bash

check_and_set_guard "_KDOITALL_APP_SAFE_MODE_COMMAND_LOADED" || return 0

# shellcheck source=../../app/safe-mode.sh
source "${LIB_DIR}/app/safe-mode.sh"
# shellcheck source=../../db/app-registry.sh
source "${LIB_DIR}/db/app-registry.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/safe-mode.sh
source "${LIB_DIR}/db/safe-mode.sh"

app_safe_mode() {
    local app_id="$1"
    local function_name="app_safe_mode"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate app_id provided
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        echo "Usage: kdoitall app safe-mode <app_id>" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate app exists
    if ! db_application_exists "$app_id"; then
        debug_error "$function_name" "$ERR_APP_NOT_FOUND" "$app_id"
        echo "Error: Application '$app_id' not found in database" >&2
        echo "Run 'kdoitall app scan' to discover applications" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if app has desktop launch capability
    local has_desktop
    has_desktop=$(db_get_app_has_desktop_launch "$app_id")
    
    if [[ "$has_desktop" != "1" ]]; then
        echo "Error: Application '$app_id' does not support desktop launch" >&2
        echo "Safe mode is only for desktop-launched applications" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if already completed
    local already_completed
    already_completed=$(db_get_safe_mode_completed "$app_id")
    
    if [[ "$already_completed" == "1" ]]; then
        echo "Application '$app_id' has already completed safe mode." >&3
        read -r -p "Run safe mode again (re-validate)? [y/N]: " revalidate
        revalidate=$(echo "$revalidate" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$revalidate" != "y" ]]; then
            debug_function_exit "$function_name"
            return 0
        fi
        
        # Clear previous validation
        db_clear_safe_mode_data "$app_id"
    fi
    
    # Run safe mode
    if ! prepare_safe_mode_environment; then
        debug_error "$function_name" "$ERR_SAFE_MODE_CANCELLED" "Environment prep cancelled"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if ! safe_mode_launch_and_detect "$app_id"; then
        debug_error "$function_name" "$ERR_SAFE_MODE_FAILED" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "✅ Safe mode complete for '$app_id'" >&3
    debug_function_exit "$function_name"
    return 0
}
