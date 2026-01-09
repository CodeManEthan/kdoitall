#!/bin/bash

check_and_set_guard "_KDOITALL_DB_APP_REGISTRY_LOADED" || return 0

db_add_application() {
    local app_id="$1"
    local display_name="$2"
    local desktop_file_path="$3"
    local app_file_path="$4"
    local terminal_command="$5"
    local app_class="$6"
    local has_terminal_launch="$7"
    local has_desktop_launch="$8"
    local function_name="db_add_application"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$display_name" || return 1
    validate_parameter_pass "$desktop_file_path" || return 1
    validate_parameter_pass "$has_terminal_launch" || return 1
    validate_parameter_pass "$has_desktop_launch" || return 1
    
    has_terminal_launch=$(normalize_boolean "$has_terminal_launch")
    has_desktop_launch=$(normalize_boolean "$has_desktop_launch")

    # Execute INSERT OR REPLACE
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :display_name '$display_name'" \
        -cmd ".param set :desktop_file '$desktop_file_path'" \
        -cmd ".param set :app_file '$app_file_path'" \
        -cmd ".param set :terminal_cmd '$terminal_command'" \
        -cmd ".param set :app_class '$app_class'" \
        -cmd ".param set :has_terminal '$has_terminal_launch'" \
        -cmd ".param set :has_desktop '$has_desktop_launch'" \
        "INSERT OR REPLACE INTO applications (
            app_id, display_name, desktop_file_path,
            app_file_path, terminal_command, app_class,
            has_terminal_launch, has_desktop_launch,
            last_validated
        ) VALUES (
            :app_id, :display_name, :desktop_file,
            :app_file, :terminal_cmd, :app_class,
            :has_terminal, :has_desktop,
            datetime('now')
        );" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add application: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Added/updated application: $app_id ($display_name)"
    debug_function_exit "$function_name"
    return 0
}

db_get_application() {
    local app_id="$1"
    local function_name="db_get_application"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    # Query database with all fields
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_id, display_name, desktop_file_path,
                app_file_path, terminal_command, app_class,
                has_terminal_launch, has_desktop_launch,
                last_validated, safe_mode_completed, safe_mode_timestamp,
                launch_mode, supports_pid_validation, expected_executable_path,
                expected_process_name, window_title_pattern, 
                expected_launch_time_ms
         FROM applications
         WHERE app_id = :app_id;" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Retrieved application: $app_id"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_list_applications() {
    local filter="${1:-all}"
    local function_name="db_list_applications"
    local query=""
    local result=""
    
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
    result=$(sqlite3 "$KDOITALL_DB" "$query" 2>/dev/null)
    
    # Note: Empty result is not an error - just means no apps match filter
    debug_log "$function_name" "Listed applications with filter: $filter"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_application_exists() {
    local app_id="$1"
    local function_name="db_application_exists"
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    # Check existence
    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COUNT(*) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    if [[ "$count" -eq 1 ]]; then
        debug_log "$function_name" "Application exists: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Application does not exist: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_application_not_exists() {
    local app_id="$1"
    local function_name="db_application_not_exists"
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    # Check existence
    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COUNT(*) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    if [[ "$count" -eq 1 ]]; then
        debug_log "$function_name" "Application exists: $app_id"
        debug_function_exit "$function_name"
        return 1
    else
        debug_log "$function_name" "Application does not exist: $app_id"
        debug_function_exit "$function_name"
        return 0
    fi
}

db_delete_application() {
    local app_id="$1"
    local function_name="db_delete_application"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    db_application_exists "$app_id" || return 1
    
    # Delete application
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "DELETE FROM applications WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Deleted application: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete application: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_update_validation_timestamp() {
    local app_id="$1"
    local function_name="db_update_validation_timestamp"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    # Update timestamp
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "UPDATE applications 
         SET last_validated = datetime('now')
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Updated validation timestamp for: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_applications_needing_validation() {
    local days="${1:-90}"
    local function_name="db_get_applications_needing_validation"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "days must be a number: $days"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Query applications needing validation
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :days '$days'" \
        "SELECT app_id
         FROM applications
         WHERE last_validated IS NULL 
            OR last_validated < datetime('now', '-' || :days || ' days')
         ORDER BY last_validated ASC;" 2>/dev/null)
    
    # Note: Empty result is not an error - just means all apps are validated
    debug_log "$function_name" "Found applications needing validation (older than $days days)"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_terminal_command() {
    local app_id="$1"
    local function_name="db_get_terminal_command"
    local result=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT terminal_command FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved terminal_command for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_app_file_path() {
    local app_id="$1"
    local function_name="db_get_app_file_path"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_file_path FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved app_file_path for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}