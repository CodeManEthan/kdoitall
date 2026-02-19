#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_APP_LOADED" || return 0

db_add_application() {
    local app_id="$1"
    local display_name="$2"
    local desktop_file_path="$3"
    local app_directory_path="$4"
    local terminal_command="$5"
    local app_class="$6"
    local has_terminal_launch="$7"
    local has_desktop_launch="$8"
    local function_name="db_add_application"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$display_name" "display_name" || return 1
    validate_parameter_pass "$desktop_file_path" "desktop_file_path" || return 1
    validate_parameter_pass "$has_terminal_launch" "has_terminal_launch" || return 1
    validate_parameter_pass "$has_desktop_launch" "has_desktop_launch" || return 1
    
    has_terminal_launch=$(normalize_boolean "$has_terminal_launch")
    has_desktop_launch=$(normalize_boolean "$has_desktop_launch")

    # Execute INSERT OR REPLACE
    db_query \
        "INSERT OR REPLACE INTO applications (
            app_id, display_name, desktop_file_path,
            app_directory_path, terminal_command, app_class,
            has_terminal_launch, has_desktop_launch,
            last_validated
        ) VALUES (
            :app_id, :display_name, :desktop_file,
            :app_directory_path, :terminal_command, :app_class,
            :has_terminal_launch, :has_desktop_launch,
            datetime('now')
        );" \
        ":app_id" "$app_id" \
        ":display_name" "$display_name" \
        ":desktop_file" "$desktop_file_path" \
        ":app_directory_path" "$app_directory_path" \
        ":terminal_command" "$terminal_command" \
        ":app_class" "$app_class" \
        ":has_terminal_launch" "$has_terminal_launch" \
        ":has_desktop_launch" "$has_desktop_launch"
    
    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add application: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Added/updated application: $app_id ($display_name)"
    debug_function_exit "$function_name"
    return 0
}

db_delete_application() {
    local app_id="$1"
    local function_name="db_delete_application"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    db_application_exists "$app_id" || return 1
    
    # Delete application
    db_query \
        "DELETE FROM applications WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Deleted application: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete application: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_clear_safe_mode_data() {
    local app_id="$1"
    local function_name="db_clear_safe_mode_data"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "UPDATE applications 
         SET safe_mode_completed = FALSE,
             safe_mode_timestamp = NULL,
             app_class = NULL
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Cleared safe mode data for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_application_exists() {
    local app_id="$1"
    local function_name="db_application_exists"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    # Check existence
    db_query \
        "SELECT COUNT(*) FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Application exists: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Application does not exist: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_list_applications() {
    local filter="${1:-all}"
    local function_name="db_list_applications"
    local query=""
    
    debug_function_enter "$function_name" "$@"
    
    # Build query based on filter
    case "$filter" in
        all)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   ORDER BY display_name;"
            ;;
        terminal)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_terminal_launch = TRUE
                   ORDER BY display_name;"
            ;;
        desktop)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_desktop_launch = TRUE
                   ORDER BY display_name;"
            ;;
        *)
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid filter: $filter"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # Execute query
    db_query "$query"
    
    # Note: Empty result is not an error - just means no apps match filter
    debug_log "$function_name" "Listed applications with filter: $filter"
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_applications_needing_validation() {
    local days="${1:-90}"
    local function_name="db_get_applications_needing_validation"
    
    debug_function_enter "$function_name" "$@"
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "days must be a number: $days"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Query applications needing validation
    db_query \
        "SELECT app_id
         FROM applications
         WHERE last_validated IS NULL 
            OR last_validated < datetime('now', '-' || :days || ' days')
         ORDER BY last_validated ASC;" \
        ":days" "$days"
    
    # Note: Empty result is not an error - just means all apps are validated
    debug_log "$function_name" "Found applications needing validation (older than $days days)"
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_application() {
    local app_id="$1"
    local function_name="db_get_application"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    # Query database with all fields
    db_query \
        "SELECT app_id, display_name, desktop_file_path,
                app_directory_path, terminal_command, app_class,
                has_terminal_launch, has_desktop_launch,
                last_validated, safe_mode_completed, safe_mode_timestamp,
                launch_mode, supports_pid_validation, executable_path,
                process_name, window_title_pattern, 
                launch_time_ms
         FROM applications
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result="${DB_RESULT[0]}"
    
    debug_log "$function_name" "Retrieved application: $app_id"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_display_name() {
    local app_id="$1"
    local function_name="db_get_display_name"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    # Query database with display_name
    db_query \
        "SELECT display_name
         FROM applications
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result="${DB_RESULT[0]}"
    
    debug_log "$function_name" "Retrieved display_name for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_app_class() {
    local app_id="$1"
    local function_name="db_get_app_class"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT app_class FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Retrieved app_class for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_app_class() {
    local app_id="$1"
    local class="$2"
    local function_name="db_set_app_class"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    validate_parameter_pass "$class" "class" || return 1
    
    db_query \
        "UPDATE applications 
         SET app_class = :class
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id" \
        ":class" "$class"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set app_class for $app_id: $class"
    debug_function_exit "$function_name"
    return 0
}

db_get_app_has_desktop_launch() {
    local app_id="$1"
    local function_name="db_get_app_has_desktop_launch"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT has_desktop_launch FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Has desktop launch for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_app_has_terminal_launch() {
    local app_id="$1"
    local function_name="db_get_app_has_terminal_launch"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT has_terminal_launch FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Has terminal launch for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_launch_mode() {
    local app_id="$1"
    local function_name="db_get_launch_mode"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT launch_mode FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Launch mode for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_launch_mode() {
    local app_id="$1"
    local launch_mode="$2"
    local function_name="db_set_launch_mode"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$launch_mode" "launch_mode" || return 1
    
    # Validate launch_mode value
    if [[ "$launch_mode" != "multi" && "$launch_mode" != "single" && "$launch_mode" != "unique" && "$launch_mode" != "unknown" && "$launch_mode" != "single_or_unique" ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "launch_mode must be 'multi', 'unique', 'single', 'single_or_unique' or 'unknown', got: $launch_mode"
        debug_function_exit "$function_name"
        return 1
    fi
    
    db_query \
        "UPDATE applications 
         SET launch_mode = :launch_mode
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id" \
        ":launch_mode" "$launch_mode"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set launch_mode='$launch_mode' for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_get_window_title_pattern() {
    local app_id="$1"
    local function_name="db_get_window_title_pattern"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT COALESCE(window_title_pattern, '') FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Window title pattern for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_window_title_pattern() {
    local app_id="$1"
    local pattern="$2"
    local function_name="db_set_window_title_pattern"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$pattern" "pattern" || return 1
    
    db_query \
        "UPDATE applications 
         SET window_title_pattern = :pattern
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id" \
        ":pattern" "$pattern"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set window title pattern='$pattern' for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_get_supports_pid_validation() {
    local app_id="$1"
    local function_name="db_get_supports_pid_validation"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT supports_pid_validation FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Supports PID validation for $app_id: ${result:-NULL}"
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
    local supports_pid_bool=""
    supports_pid_bool=0
    [[ "$supports_pid" == "true" ]] && supports_pid_bool=1
    
    db_query \
        "UPDATE applications 
         SET supports_pid_validation = :supports_pid,
             process_name = :process_name,
             executable_path = :executable_path
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id" \
        ":supports_pid" "$supports_pid_bool" \
        ":process_name" "$process_name" \
        ":executable_path" "$executable_path"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
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
    
    db_query \
        "SELECT 
            CASE WHEN supports_pid_validation = 1 THEN 'true' ELSE 'false' END,
            COALESCE(process_name, ''),
            COALESCE(executable_path, '')
         FROM applications 
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "PID validation data for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_launch_time() {
    local app_id="$1"
    local expected_time=""
    local function_name="db_get_launch_time"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT COALESCE(launch_time_ms, 5000) FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    expected_time="${DB_RESULT[0]:-5000}"
    
    debug_log "$function_name" "Expected launch time for $app_id: ${expected_time}ms"
    debug_function_exit "$function_name"
    echo "$expected_time"
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
    local current_samples=""
    local current_expected=""
    db_query \
        "SELECT COALESCE(launch_time_samples, 0) FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    current_samples="${DB_RESULT[0]:-0}"

    db_query \
        "SELECT COALESCE(launch_time_ms, 0) FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    current_expected="${DB_RESULT[0]:-0}"
    
    # Calculate new expected time (rolling average with buffer)
    local new_expected=""
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
    db_query \
        "UPDATE applications 
         SET last_launch_time_ms = :measured,
             launch_time_ms = :expected,
             launch_time_samples = launch_time_samples + 1
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id" \
        ":measured" "$measured_time_ms" \
        ":expected" "$new_expected"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Updated launch time: measured=${measured_time_ms}ms, expected=${new_expected}ms"
    debug_function_exit "$function_name"
    return 0
}

db_get_launch_time_samples() {
    local app_id="$1"
    local samples=""
    local function_name="db_get_launch_time_samples"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT COALESCE(launch_time_samples, 0) FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    samples="${DB_RESULT[0]:-0}"
    
    debug_log "$function_name" "Launch time samples for $app_id: $samples"
    debug_function_exit "$function_name"
    echo "$samples"
    return 0
}

db_get_app_directory_path() {
    local app_id="$1"
    local function_name="db_get_app_directory_path"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT app_directory_path FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Retrieved app_directory_path for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_terminal_command() {
    local app_id="$1"
    local function_name="db_get_terminal_command"
    local result=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT terminal_command FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Retrieved terminal_command for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_safe_mode_completed() {
    local app_id="$1"
    local function_name="db_get_safe_mode_completed"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT safe_mode_completed FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Safe mode completed for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_safe_mode_completed() {
    local app_id="$1"
    local function_name="db_set_safe_mode_completed"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "UPDATE applications 
         SET safe_mode_completed = TRUE,
             safe_mode_timestamp = datetime('now')
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Marked safe mode completed for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_set_requires_safe_mode() {
    local app_id="$1"
    local requires="$2"  # TRUE or FALSE
    local function_name="db_set_requires_safe_mode"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$requires" "requires" || return 1
    
    requires=$(normalize_boolean "$requires")
    
    db_query \
        "UPDATE applications 
         SET requires_safe_mode = :requires
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id" \
        ":requires" "$requires"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set requires_safe_mode=$requires for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_get_pending_safe_mode_apps() {
    local function_name="db_get_pending_safe_mode_apps"
    
    debug_function_enter "$function_name"
    
    # Get apps that require safe mode but haven't completed it
    db_query \
        "SELECT app_id, display_name 
         FROM applications 
         WHERE requires_safe_mode = TRUE 
         AND safe_mode_completed = FALSE
         ORDER BY display_name;"
    
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_count_pending_safe_mode_apps() {
    local function_name="db_count_pending_safe_mode_apps"
    
    debug_function_enter "$function_name"
    
    db_query \
        "SELECT COUNT(*) 
         FROM applications 
         WHERE requires_safe_mode = TRUE 
         AND safe_mode_completed = FALSE;"
    
    debug_function_exit "$function_name"
    echo "${DB_RESULT[0]:-0}"
    return 0
}

db_update_validation_timestamp() {
    local app_id="$1"
    local function_name="db_update_validation_timestamp"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    # Update timestamp
    db_query \
        "UPDATE applications 
         SET last_validated = datetime('now')
         WHERE app_id = :app_id;
         SELECT changes();" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Updated validation timestamp for: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}