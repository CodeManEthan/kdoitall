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
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add application: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Added/updated application: $app_id ($display_name)"
    debug_function_exit "$function_name"
    return 0
}

db_add_application_full() {
    local app_id="$1"
    local display_name="$2"
    local desktop_file_path="$3"
    local app_directory_path="$4"
    local terminal_command="$5"
    local app_class="$6"
    local has_terminal_launch="$7"
    local has_desktop_launch="$8"
    local launch_mode="${9:-}"
    local window_title_pattern="${10:-}"
    local supports_pid_validation="${11:-}"
    local process_name="${12:-}"
    local app_name="${13:-}"
    local function_name="db_add_application_full"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$display_name" "display_name" || return 1
    validate_parameter_pass "$desktop_file_path" "desktop_file_path" || return 1
    validate_parameter_pass "$has_terminal_launch" "has_terminal_launch" || return 1
    validate_parameter_pass "$has_desktop_launch" "has_desktop_launch" || return 1
    
    has_terminal_launch=$(normalize_boolean "$has_terminal_launch")
    has_desktop_launch=$(normalize_boolean "$has_desktop_launch")

    # Convert supports_pid_validation to SQLite boolean if provided
    local supports_pid_bool=""
    if [[ -n "$supports_pid_validation" ]]; then
        supports_pid_bool=0
        [[ "$supports_pid_validation" == "1" || "$supports_pid_validation" == "true" ]] && supports_pid_bool=1
    fi

    db_query \
        "INSERT OR REPLACE INTO applications (
            app_id, app_name, display_name, desktop_file_path,
            app_directory_path, terminal_command, app_class,
            has_terminal_launch, has_desktop_launch,
            launch_mode, window_title_pattern,
            supports_pid_validation, process_name,
            last_validated
        ) VALUES (
            :app_id,
            CASE WHEN :app_name != '' THEN :app_name ELSE NULL END,
            :display_name, :desktop_file,
            :app_directory_path, :terminal_command,
            CASE WHEN :app_class != '' THEN :app_class ELSE NULL END,
            :has_terminal_launch, :has_desktop_launch,
            CASE WHEN :launch_mode != '' THEN :launch_mode ELSE NULL END,
            CASE WHEN :title_pattern != '' THEN :title_pattern ELSE NULL END,
            CASE WHEN :supports_pid != '' THEN :supports_pid ELSE NULL END,
            CASE WHEN :process_name != '' THEN :process_name ELSE NULL END,
            datetime('now')
        );" \
        ":app_id" "$app_id" \
        ":app_name" "$app_name" \
        ":display_name" "$display_name" \
        ":desktop_file" "$desktop_file_path" \
        ":app_directory_path" "$app_directory_path" \
        ":terminal_command" "$terminal_command" \
        ":app_class" "$app_class" \
        ":has_terminal_launch" "$has_terminal_launch" \
        ":has_desktop_launch" "$has_desktop_launch" \
        ":launch_mode" "$launch_mode" \
        ":title_pattern" "$window_title_pattern" \
        ":supports_pid" "$supports_pid_bool" \
        ":process_name" "$process_name"
    
    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add application: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Added/updated application (full): $app_id ($display_name)"
    debug_function_exit "$function_name"
    return 0
}

db_upsert_application_scan() {
    local app_id="$1"
    local display_name="$2"
    local desktop_file_path="$3"
    local app_directory_path="$4"
    local terminal_command="$5"
    local app_class="$6"
    local has_terminal_launch="$7"
    local has_desktop_launch="$8"
    local launch_mode="${9:-}"
    local window_title_pattern="${10:-}"
    local supports_pid_validation="${11:-}"
    local process_name="${12:-}"
    local app_name="${13:-}"
    local function_name="db_upsert_application_scan"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$display_name" "display_name" || return 1
    validate_parameter_pass "$desktop_file_path" "desktop_file_path" || return 1
    validate_parameter_pass "$has_terminal_launch" "has_terminal_launch" || return 1
    validate_parameter_pass "$has_desktop_launch" "has_desktop_launch" || return 1

    has_terminal_launch=$(normalize_boolean "$has_terminal_launch")
    has_desktop_launch=$(normalize_boolean "$has_desktop_launch")

    # Convert supports_pid_validation to SQLite boolean if provided
    local supports_pid_bool=""
    if [[ -n "$supports_pid_validation" ]]; then
        supports_pid_bool=0
        [[ "$supports_pid_validation" == "1" || "$supports_pid_validation" == "true" ]] && supports_pid_bool=1
    fi

    if db_application_exists "$app_id"; then
        # UPDATE existing app: only overwrite scan-sourced fields
        # Registry-sourced fields only update when the new value is non-empty
        # app_name is only overwritten if app_name_manual is not set
        db_query \
            "UPDATE applications SET
                display_name = :display_name,
                desktop_file_path = :desktop_file,
                app_directory_path = :app_directory_path,
                terminal_command = :terminal_command,
                has_terminal_launch = :has_terminal_launch,
                has_desktop_launch = :has_desktop_launch,
                app_name = CASE
                    WHEN app_name_manual = 1 THEN app_name
                    WHEN :app_name != '' THEN :app_name
                    ELSE app_name END,
                app_class = CASE WHEN :app_class != '' THEN :app_class ELSE app_class END,
                launch_mode = CASE WHEN :launch_mode != '' THEN :launch_mode ELSE launch_mode END,
                window_title_pattern = CASE WHEN :title_pattern != '' THEN :title_pattern ELSE window_title_pattern END,
                supports_pid_validation = CASE WHEN :supports_pid != '' THEN :supports_pid ELSE supports_pid_validation END,
                process_name = CASE WHEN :process_name != '' THEN :process_name ELSE process_name END,
                last_validated = datetime('now')
            WHERE app_id = :app_id;" \
            ":app_id" "$app_id" \
            ":display_name" "$display_name" \
            ":desktop_file" "$desktop_file_path" \
            ":app_directory_path" "$app_directory_path" \
            ":terminal_command" "$terminal_command" \
            ":has_terminal_launch" "$has_terminal_launch" \
            ":has_desktop_launch" "$has_desktop_launch" \
            ":app_name" "$app_name" \
            ":app_class" "$app_class" \
            ":launch_mode" "$launch_mode" \
            ":title_pattern" "$window_title_pattern" \
            ":supports_pid" "$supports_pid_bool" \
            ":process_name" "$process_name"

        if [[ "$DB_STATUS" != "OK" ]]; then
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to update application: $app_id ($DB_ERROR)"
            debug_function_exit "$function_name"
            return 1
        fi

        debug_log "$function_name" "Updated existing application: $app_id ($display_name)"
    else
        # INSERT new app with all provided data
        db_query \
            "INSERT INTO applications (
                app_id, app_name, display_name, desktop_file_path,
                app_directory_path, terminal_command, app_class,
                has_terminal_launch, has_desktop_launch,
                launch_mode, window_title_pattern,
                supports_pid_validation, process_name,
                last_validated
            ) VALUES (
                :app_id,
                CASE WHEN :app_name != '' THEN :app_name ELSE NULL END,
                :display_name, :desktop_file,
                :app_directory_path, :terminal_command,
                CASE WHEN :app_class != '' THEN :app_class ELSE NULL END,
                :has_terminal_launch, :has_desktop_launch,
                CASE WHEN :launch_mode != '' THEN :launch_mode ELSE NULL END,
                CASE WHEN :title_pattern != '' THEN :title_pattern ELSE NULL END,
                CASE WHEN :supports_pid != '' THEN :supports_pid ELSE NULL END,
                CASE WHEN :process_name != '' THEN :process_name ELSE NULL END,
                datetime('now')
            );" \
            ":app_id" "$app_id" \
            ":app_name" "$app_name" \
            ":display_name" "$display_name" \
            ":desktop_file" "$desktop_file_path" \
            ":app_directory_path" "$app_directory_path" \
            ":terminal_command" "$terminal_command" \
            ":app_class" "$app_class" \
            ":has_terminal_launch" "$has_terminal_launch" \
            ":has_desktop_launch" "$has_desktop_launch" \
            ":launch_mode" "$launch_mode" \
            ":title_pattern" "$window_title_pattern" \
            ":supports_pid" "$supports_pid_bool" \
            ":process_name" "$process_name"

        if [[ "$DB_STATUS" != "OK" ]]; then
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to insert application: $app_id ($DB_ERROR)"
            debug_function_exit "$function_name"
            return 1
        fi

        debug_log "$function_name" "Inserted new application: $app_id ($display_name)"
    fi

    debug_function_exit "$function_name"
    return 0
}

db_remove_uninstalled_applications() {
    local found_app_ids="$1"
    local function_name="db_remove_uninstalled_applications"
    local removed_count=0

    debug_function_enter "$function_name"

    # Get all existing app_ids from database
    local existing_ids=""
    db_query "SELECT app_id FROM applications;"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to query existing applications ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_log "$function_name" "No existing applications to check"
        debug_function_exit "$function_name"
        echo "0"
        return 0
    fi

    # Check each existing app_id against the found list
    local db_app_id=""
    for db_app_id in "${DB_RESULT[@]}"; do
        [[ -z "$db_app_id" ]] && continue

        # Check if this app_id was found during the scan
        local found=false
        local found_id=""
        while IFS= read -r found_id; do
            if [[ "$found_id" == "$db_app_id" ]]; then
                found=true
                break
            fi
        done <<< "$found_app_ids"

        if [[ "$found" == "false" ]]; then
            debug_log "$function_name" "Removing uninstalled application: $db_app_id"
            if db_delete_application "$db_app_id"; then
                ((removed_count++))
            else
                debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to remove: $db_app_id"
            fi
        fi
    done

    debug_log "$function_name" "Removed $removed_count uninstalled applications"
    debug_function_exit "$function_name"
    echo "$removed_count"
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
        "DELETE FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Deleted application: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete application: $app_id ($DB_ERROR)"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
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
                   ORDER BY display_name COLLATE NOCASE;"
            ;;
        terminal)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_terminal_launch = TRUE
                   ORDER BY display_name COLLATE NOCASE;"
            ;;
        desktop)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_desktop_launch = TRUE
                   ORDER BY display_name COLLATE NOCASE;"
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
        "SELECT app_id, app_name, display_name, desktop_file_path,
                app_directory_path, terminal_command, app_class,
                has_terminal_launch, has_desktop_launch,
                last_validated, safe_mode_completed, safe_mode_timestamp,
                launch_mode, supports_pid_validation, executable_path,
                process_name, window_title_pattern, 
                launch_time_ms, has_splash_window, splash_duration_ms
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

db_get_app_launch_properties() {
    local app_id="$1"
    local function_name="db_get_app_launch_properties"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT COALESCE(app_class, ''),
                COALESCE(window_title_pattern, ''),
                COALESCE(launch_mode, ''),
                COALESCE(launch_time_ms, 5000),
                COALESCE(has_splash_window, 'unknown'),
                splash_duration_ms
         FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result="${DB_RESULT[0]}"
    
    debug_log "$function_name" "Retrieved launch properties for $app_id: $result"
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

db_find_apps_by_display_name() {
    local name="$1"
    local function_name="db_find_apps_by_display_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$name" "name" || return 1

    db_query \
        "SELECT app_id, display_name
         FROM applications
         WHERE LOWER(display_name) = LOWER(:name)
         ORDER BY app_id;" \
        ":name" "$name"

    debug_log "$function_name" "Found ${#DB_RESULT[@]} app(s) matching display name: $name"
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
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

db_get_app_name() {
    local app_id="$1"
    local function_name="db_get_app_name"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    db_query \
        "SELECT app_name FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    result="${DB_RESULT[0]:-}"
    
    debug_log "$function_name" "Retrieved app_name for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_class_to_app_name_map() {
    local function_name="db_get_class_to_app_name_map"
    
    debug_function_enter "$function_name"
    
    db_query \
        "SELECT app_class, app_name FROM applications
         WHERE app_name IS NOT NULL AND app_class IS NOT NULL;"
    
    debug_log "$function_name" "Retrieved ${#DB_RESULT[@]} class-to-app_name mappings"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":class" "$class"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Set app_class for $app_id: $class"
    debug_function_exit "$function_name"
    return 0
}

db_set_has_splash_window() {
    local app_id="$1"
    local has_splash_window="$2"
    local function_name="db_set_has_splash_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$has_splash_window" "has_splash_window" || return 1

    db_query \
        "UPDATE applications
         SET has_splash_window = :has_splash_window
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":has_splash_window" "$has_splash_window"

    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Set has_splash_window for $app_id: $has_splash_window"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":launch_mode" "$launch_mode"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":pattern" "$pattern"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":supports_pid" "$supports_pid_bool" \
        ":process_name" "$process_name" \
        ":executable_path" "$executable_path"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
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
    
    # Single UPDATE with rolling average computed in SQL:
    # - First sample (samples=0): measured * 3/2 (50% buffer)
    # - Subsequent: ((avg * samples + measured) / (samples + 1)) * 5/4 (25% buffer)
    db_query \
        "UPDATE applications SET
            last_launch_time_ms = CAST(:measured AS INTEGER),
            launch_time_ms = CASE
                WHEN COALESCE(launch_time_samples, 0) = 0
                THEN CAST(:measured AS INTEGER) * 3 / 2
                ELSE (COALESCE(launch_time_ms, 0) * COALESCE(launch_time_samples, 0) + CAST(:measured AS INTEGER))
                     / (COALESCE(launch_time_samples, 0) + 1) * 5 / 4
            END,
            launch_time_samples = COALESCE(launch_time_samples, 0) + 1
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":measured" "$measured_time_ms"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Updated launch time for $app_id: measured=${measured_time_ms}ms"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Marked safe mode completed for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_set_safe_mode_results() {
    local app_id="$1"
    local class="$2"
    local supports_pid="$3"
    local process_name="$4"
    local executable_path="$5"
    local title_pattern="$6"
    local launch_mode="$7"
    local has_splash_window="${8:-false}"
    local splash_duration_ms="${9:-}"
    local function_name="db_set_safe_mode_results"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$class" "class" || return 1
    validate_parameter_pass "$launch_mode" "launch_mode" || return 1

    # Convert supports_pid to SQLite boolean
    local supports_pid_bool=""
    supports_pid_bool=0
    [[ "$supports_pid" == "true" ]] && supports_pid_bool=1

    # Single UPDATE with all safe-mode metadata
    # title_pattern is optional — keep existing value if empty
    # has_splash_window is passed as string directly ("true"/"false")
    # splash_duration_ms is optional — keep existing value if empty
    db_query \
        "UPDATE applications SET
            app_class = :class,
            supports_pid_validation = :supports_pid,
            process_name = :process_name,
            executable_path = :exe_path,
            window_title_pattern = CASE WHEN :title_pattern != '' THEN :title_pattern ELSE window_title_pattern END,
            launch_mode = :launch_mode,
            has_splash_window = :has_splash_window,
            splash_duration_ms = CASE WHEN :splash_duration_ms != '' THEN CAST(:splash_duration_ms AS INTEGER) ELSE splash_duration_ms END,
            safe_mode_completed = TRUE,
            safe_mode_timestamp = datetime('now')
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":class" "$class" \
        ":supports_pid" "$supports_pid_bool" \
        ":process_name" "$process_name" \
        ":exe_path" "$executable_path" \
        ":title_pattern" "$title_pattern" \
        ":launch_mode" "$launch_mode" \
        ":has_splash_window" "$has_splash_window" \
        ":splash_duration_ms" "$splash_duration_ms"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Stored safe mode results for $app_id: class=$class, mode=$launch_mode"
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
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":requires" "$requires"
    
    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
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

db_get_apps_needing_safe_mode() {
    local workspace_name="$1"
    local strictness="${2:-relaxed}"
    local function_name="db_get_apps_needing_safe_mode"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Build metadata condition based on strictness level
    local metadata_condition=""
    if [[ "$strictness" == "strict" ]]; then
        # Prompt if app class, launch mode, or splash window is missing
        metadata_condition="AND (
               (a.app_class IS NULL OR a.app_class = '')
               OR (a.launch_mode IS NULL OR a.launch_mode = '')
               OR a.has_splash_window = 'unknown'
           )"
    else
        # Relaxed: only prompt if app class is missing
        metadata_condition="AND (a.app_class IS NULL OR a.app_class = '')"
    fi

    db_query \
        "SELECT DISTINCT wd.app_id
         FROM window_definitions wd
         JOIN applications a ON wd.app_id = a.app_id
         WHERE wd.workspace_name = :workspace
           ${metadata_condition}
           AND COALESCE(a.safe_mode_completed, 0) != 1
         ORDER BY wd.app_id;" \
        ":workspace" "$workspace_name"
    
    debug_log "$function_name" "Found ${#DB_RESULT[@]} apps needing safe mode for workspace: $workspace_name (strictness: $strictness)"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_mark_apps_requiring_safe_mode() {
    local workspace_name="$1"
    local strictness="${2:-relaxed}"
    local function_name="db_mark_apps_requiring_safe_mode"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Build metadata condition based on strictness level
    local metadata_condition=""
    if [[ "$strictness" == "strict" ]]; then
        metadata_condition="AND (
                   (a.app_class IS NULL OR a.app_class = '')
                   OR (a.launch_mode IS NULL OR a.launch_mode = '')
                   OR a.has_splash_window = 'unknown'
               )"
    else
        metadata_condition="AND (a.app_class IS NULL OR a.app_class = '')"
    fi

    # Batch UPDATE: mark all qualifying apps in one query
    db_query \
        "UPDATE applications SET requires_safe_mode = TRUE
         WHERE app_id IN (
             SELECT DISTINCT wd.app_id
             FROM window_definitions wd
             JOIN applications a ON wd.app_id = a.app_id
             WHERE wd.workspace_name = :workspace
               ${metadata_condition}
               AND COALESCE(a.safe_mode_completed, 0) != 1
         );" \
        ":workspace" "$workspace_name"
    
    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to mark apps requiring safe mode ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Marked ${DB_RESULT[0]:-0} apps requiring safe mode for workspace: $workspace_name (strictness: $strictness)"
    debug_function_exit "$function_name"
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
         WHERE app_id = :app_id;" \
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

db_ensure_app_name_manual_column() {
    local function_name="db_ensure_app_name_manual_column"

    debug_function_enter "$function_name"

    db_query \
        "SELECT COUNT(*) FROM pragma_table_info('applications') WHERE name='app_name_manual';"

    if [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        db_query "ALTER TABLE applications ADD COLUMN app_name_manual BOOLEAN DEFAULT 0;"
        debug_log "$function_name" "Added app_name_manual column to applications table"
    else
        debug_log "$function_name" "app_name_manual column already exists"
    fi

    debug_function_exit "$function_name"
    return 0
}

db_get_manual_app_names() {
    local function_name="db_get_manual_app_names"

    debug_function_enter "$function_name"

    db_query \
        "SELECT app_id, app_name FROM applications
         WHERE app_name_manual = 1 AND app_name IS NOT NULL;"

    debug_log "$function_name" "Retrieved ${#DB_RESULT[@]} manually-set app names"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_set_app_name() {
    local app_id="$1"
    local new_name="$2"
    local manual="${3:-0}"
    local function_name="db_set_app_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$new_name" "new_name" || return 1

    manual=$(normalize_boolean "$manual")

    db_query \
        "UPDATE applications SET
            app_name = :new_name,
            app_name_manual = :manual
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":new_name" "$new_name" \
        ":manual" "$manual"

    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -ne 1 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to set app_name for $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Set app_name='$new_name' (manual=$manual) for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_check_app_name_exists() {
    local name="$1"
    local exclude_app_id="${2:-}"
    local function_name="db_check_app_name_exists"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$name" "name" || return 1

    if [[ -n "$exclude_app_id" ]]; then
        db_query \
            "SELECT COUNT(*) FROM applications
             WHERE app_name = :name AND app_id != :exclude_id;" \
            ":name" "$name" \
            ":exclude_id" "$exclude_app_id"
    else
        db_query \
            "SELECT COUNT(*) FROM applications WHERE app_name = :name;" \
            ":name" "$name"
    fi

    if [[ "${DB_RESULT[0]:-0}" -ge 1 ]]; then
        debug_log "$function_name" "app_name '$name' already exists"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "app_name '$name' is available"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_update_app_windows_app_name() {
    local app_id="$1"
    local new_name="$2"
    local function_name="db_update_app_windows_app_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$new_name" "new_name" || return 1

    db_query \
        "UPDATE app_windows SET app_name = :new_name WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":new_name" "$new_name"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to update app_windows for $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Updated app_windows app_name to '$new_name' for app_id=$app_id (${DB_RESULT[0]:-0} rows)"
    debug_function_exit "$function_name"
    return 0
}