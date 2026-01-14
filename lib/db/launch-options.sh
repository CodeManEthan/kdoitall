#!/bin/bash

check_and_set_guard "_KDOITALL_DB_LAUNCH_OPTIONS_LOADED" || return 0

db_add_launch_option() {
    local app_id="$1"
    local function_name="$2"
    local description="$3"
    local display_order="${4:-0}"
    local func_name="db_add_launch_option"
    
    debug_function_enter "$func_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$function_name" "function_name" || return 1
    validate_parameter_pass "$description" "description" || return 1
    
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

db_delete_launch_options_for_app() {
    local app_id="$1"
    local function_name="db_delete_launch_options_for_app"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "DELETE FROM launch_options WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    debug_log "$function_name" "Deleted $changes launch options for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_add_launch_parameter() {
    local app_id="$1"
    local function_id="$2"
    local parameter_name="$3"
    local description="$4"
    local display_order="${5:-0}"
    local func_name="db_add_launch_parameter"
    
    debug_function_enter "$func_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$function_id" "function_id" || return 1
    validate_parameter_pass "$parameter_name" "parameter_name" || return 1
    validate_parameter_pass "$description" "description" || return 1
    
    # Execute INSERT OR REPLACE
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :function_id '$function_id'" \
        -cmd ".param set :parameter_name '$parameter_name'" \
        -cmd ".param set :description '$description'" \
        -cmd ".param set :display_order '$display_order'" \
        "INSERT OR REPLACE INTO launch_parameters (
            app_id, function_id, parameter_name, description, display_order
        ) VALUES (
            :app_id, :function_id, :parameter_name, :description, :display_order
        );" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to add launch parameter: $app_id.$function_id.$function_name"
        debug_function_exit "$func_name"
        return 1
    fi
    
    debug_log "$func_name" "Added launch parameter: $app_id.$function_id.$parameter_name"
    debug_function_exit "$func_name"
    return 0
}

db_app_has_launch_options() {
    local app_id="$1"
    local function_name="db_app_has_launch_options"
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
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

db_get_launch_options() {
    local app_id="$1"
    local function_name="db_get_launch_options"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
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

db_get_launch_option_id() {
    local app_id="$1"
    local function_name="$2"
    local func_name="db_get_launch_option_id"
    local result=""
    
    debug_function_enter "$func_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$function_name" "function_name" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :function_name '$function_name'" \
        "SELECT id FROM launch_options 
         WHERE app_id = :app_id AND function_name = :function_name;" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        debug_error "$func_name" "$ERR_DATABASE_ERROR" "Launch option not found: $app_id.$function_name"
        debug_function_exit "$func_name"
        return 1
    fi
    
    debug_log "$func_name" "Retrieved launch option ID $result for $app_id.$function_name"
    debug_function_exit "$func_name"
    echo "$result"
    return 0
}

db_get_launch_parameters() {
    local app_id="$1"
    local function_id="$2"
    local function_name="db_get_launch_parameters"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$function_id" "function_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :function_id '$function_id'" \
        "SELECT parameter_name, description 
         FROM launch_parameters 
         WHERE app_id = :app_id AND function_id = :function_id 
         ORDER BY display_order, parameter_name;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved launch parameters for $app_id.$function_id"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}