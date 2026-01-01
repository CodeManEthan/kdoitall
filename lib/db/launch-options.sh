#!/bin/bash

check_and_set_guard "_KDOITALL_DB_LAUNCH_OPTIONS_LOADED" || return 0

# ============================================================================
# Launch Options Database Functions
# ============================================================================

# ----------------------------------------------------------------------------
# db_add_launch_option()
# Add or update a launch option for an application
# ----------------------------------------------------------------------------
db_add_launch_option() {
    local app_id="$1"
    local function_name="$2"
    local description="$3"
    local display_order="${4:-0}"
    local func_name="db_add_launch_option"
    
    debug_function_enter "$func_name" "$@"
    
    # Validate required parameters
    if [[ -z "$app_id" ]]; then
        debug_error "$func_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$func_name"
        return 1
    fi
    
    if [[ -z "$function_name" ]]; then
        debug_error "$func_name" "$ERR_MISSING_PARAMETER" "function_name"
        debug_function_exit "$func_name"
        return 1
    fi
    
    if [[ -z "$description" ]]; then
        debug_error "$func_name" "$ERR_MISSING_PARAMETER" "description"
        debug_function_exit "$func_name"
        return 1
    fi
    
    # Execute INSERT OR REPLACE
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :function_name '$function_name'" \
        -cmd ".param set :description '$description'" \
        -cmd ".param set :display_order '$display_order'" \
        "INSERT OR REPLACE INTO launch_options (
            app_id, function_name, description, display_order
        ) VALUES (
            :app_id, :function_name, :description, :display_order
        );" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to add launch option: $app_id.$function_name"
        debug_function_exit "$func_name"
        return 1
    fi
    
    debug_log "$func_name" "Added launch option: $app_id.$function_name"
    debug_function_exit "$func_name"
    return 0
}

# ----------------------------------------------------------------------------
# db_get_launch_options()
# Get all launch options for an application
# Returns: function_name|description (one per line, ordered)
# ----------------------------------------------------------------------------
db_get_launch_options() {
    local app_id="$1"
    local function_name="db_get_launch_options"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT function_name, description 
         FROM launch_options 
         WHERE app_id = :app_id 
         ORDER BY display_order, function_name;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved launch options for $app_id"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_delete_launch_options_for_app()
# Delete all launch options for an application
# Used during re-scanning to clear old options before adding new ones
# ----------------------------------------------------------------------------
db_delete_launch_options_for_app() {
    local app_id="$1"
    local function_name="db_delete_launch_options_for_app"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "DELETE FROM launch_options WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    debug_log "$function_name" "Deleted $changes launch options for $app_id"
    debug_function_exit "$function_name"
    return 0
}

# ----------------------------------------------------------------------------
# db_app_has_launch_options()
# Check if an application has any launch options defined
# Returns: 0 if has options, 1 if no options
# ----------------------------------------------------------------------------
db_app_has_launch_options() {
    local app_id="$1"
    local function_name="db_app_has_launch_options"
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COUNT(*) FROM launch_options WHERE app_id = :app_id;" 2>/dev/null)
    
    if [[ "$count" -gt 0 ]]; then
        debug_log "$function_name" "Application $app_id has $count launch options"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Application $app_id has no launch options"
        debug_function_exit "$function_name"
        return 1
    fi
}