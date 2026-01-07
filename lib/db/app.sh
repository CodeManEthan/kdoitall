#!/bin/bash

check_and_set_guard "_KDOITALL_DB_APP_LOADED" || return 0

db_get_app_display_name() {
    local app_id="$1"
    local function_name="db_get_app_display_name"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT display_name FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved display name for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_app_has_desktop_launch() {
    local app_id="$1"
    local function_name="db_get_app_has_desktop_launch"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT has_desktop_launch FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Has desktop launch for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_app_class() {
    local app_id="$1"
    local function_name="db_get_app_class"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_class FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved app_class for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_app_class() {
    local app_id="$1"
    local class="$2"
    local function_name="db_set_app_class"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    validate_parameter_pass "$class" || return 1
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :class '$class'" \
        "UPDATE applications 
         SET app_class = :class
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set app_class for $app_id: $class"
    debug_function_exit "$function_name"
    return 0
}
