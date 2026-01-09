#!/bin/bash

check_and_set_guard "_KDOITALL_DB_SAFE_MODE_LOADED" || return 0

db_get_safe_mode_completed() {
    local app_id="$1"
    local function_name="db_get_safe_mode_completed"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT safe_mode_completed FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Safe mode completed for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_safe_mode_completed() {
    local app_id="$1"
    local function_name="db_set_safe_mode_completed"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "UPDATE applications 
         SET safe_mode_completed = TRUE,
             safe_mode_timestamp = datetime('now')
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Marked safe mode completed for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_clear_safe_mode_data() {
    local app_id="$1"
    local function_name="db_clear_safe_mode_data"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "UPDATE applications 
         SET safe_mode_completed = FALSE,
             safe_mode_timestamp = NULL,
             app_class = NULL
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Cleared safe mode data for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_set_launch_mode() {
    local app_id="$1"
    local launch_mode="$2"
    local function_name="db_set_launch_mode"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$launch_mode" "launch_mode" || return 1
    
    # Validate launch_mode value
    if [[ "$launch_mode" != "multi" && "$launch_mode" != "single" ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "launch_mode must be 'multi' or 'single', got: $launch_mode"
        debug_function_exit "$function_name"
        return 1
    fi
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :launch_mode '$launch_mode'" \
        "UPDATE applications 
         SET launch_mode = :launch_mode
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set launch_mode='$launch_mode' for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_get_launch_mode() {
    local app_id="$1"
    local function_name="db_get_launch_mode"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT launch_mode FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Launch mode for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_pid_validation_data() {
    local app_id="$1"
    local supports_pid="$2"
    local process_name="$3"
    local executable_path="$4"
    local function_name="db_set_pid_validation_data"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$supports_pid" "supports_pid" || return 1
    
    # Validate supports_pid value
    if [[ "$supports_pid" != "true" && "$supports_pid" != "false" ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "supports_pid must be 'true' or 'false', got: $supports_pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Convert 'true'/'false' to 1/0 for SQLite boolean
    local supports_pid_bool=0
    [[ "$supports_pid" == "true" ]] && supports_pid_bool=1
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :supports_pid '$supports_pid_bool'" \
        -cmd ".param set :process_name '$process_name'" \
        -cmd ".param set :executable_path '$executable_path'" \
        "UPDATE applications 
         SET supports_pid_validation = :supports_pid,
             expected_process_name = :process_name,
             expected_executable_path = :executable_path
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set PID validation for $app_id: supports=$supports_pid, process='$process_name', path='$executable_path'"
    debug_function_exit "$function_name"
    return 0
}

db_get_pid_validation_data() {
    local app_id="$1"
    local function_name="db_get_pid_validation_data"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT 
            CASE WHEN supports_pid_validation = 1 THEN 'true' ELSE 'false' END,
            COALESCE(expected_process_name, ''),
            COALESCE(expected_executable_path, '')
         FROM applications 
         WHERE app_id = :app_id;" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
    
    debug_log "$function_name" "PID validation data for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_supports_pid_validation() {
    local app_id="$1"
    local function_name="db_get_supports_pid_validation"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT supports_pid_validation FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Supports PID validation for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_title_pattern() {
    local app_id="$1"
    local pattern="$2"
    local function_name="db_set_title_pattern"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$pattern" "pattern" || return 1
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :pattern '$pattern'" \
        "UPDATE applications 
         SET window_title_pattern = :pattern
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set title pattern='$pattern' for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_get_title_pattern() {
    local app_id="$1"
    local function_name="db_get_title_pattern"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COALESCE(window_title_pattern, '') FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Title pattern for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_launch_time() {
    local app_id="$1"
    local measured_time_ms="$2"
    local function_name="db_set_launch_time"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$measured_time_ms" "measured_time_ms" || return 1
    
    # Get current data
    local current_samples
    local current_expected
    current_samples=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COALESCE(launch_time_samples, 0) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    current_expected=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COALESCE(expected_launch_time_ms, 0) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    # Calculate new expected time (rolling average with buffer)
    local new_expected
    if [[ "$current_samples" -eq 0 ]]; then
        # First sample: use measured time + 50% buffer
        new_expected=$(echo "scale=0; ($measured_time_ms * 3 / 2)" | bc)
    else
        # Rolling average: (current_avg * samples + new_measurement) / (samples + 1)
        local avg=""
        avg=$(echo "scale=0; ($current_expected * $current_samples + $measured_time_ms) / ($current_samples + 1)" | bc)
        # Add 25% buffer to average
        new_expected=$(echo "scale=0; ($avg * 5 / 4)" | bc)
    fi
    
    # Update database
    local changes
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :measured '$measured_time_ms'" \
        -cmd ".param set :expected '$new_expected'" \
        "UPDATE applications 
         SET last_measured_launch_time_ms = :measured,
             expected_launch_time_ms = :expected,
             launch_time_samples = launch_time_samples + 1
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Updated launch time: measured=${measured_time_ms}ms, expected=${new_expected}ms"
    debug_function_exit "$function_name"
    return 0
}

db_get_expected_launch_time() {
    local app_id="$1"
    local expected_time=""
    local function_name="db_get_expected_launch_time"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    expected_time=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COALESCE(expected_launch_time_ms, 5000) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Expected launch time for $app_id: ${expected_time}ms"
    debug_function_exit "$function_name"
    echo "$expected_time"
    return 0
}

db_get_launch_time_samples() {
    local app_id="$1"
    local samples=""
    local function_name="db_get_launch_time_samples"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    samples=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COALESCE(launch_time_samples, 0) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Launch time samples for $app_id: $samples"
    debug_function_exit "$function_name"
    echo "$samples"
    return 0
}
