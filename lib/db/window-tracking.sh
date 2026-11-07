#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_WINDOW_TRACKING_LOADED" || return 0

db_add_window() {
    local workspace_name="$1"
    local window_name="$2"
    local uuid="$3"
    local class="$4"
    local window_title="$5"
    local function_name="db_add_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$class" "class" || return 1
    
    # Add entry to 'app_windows' table
    db_query \
        "INSERT INTO app_windows (workspace_name, window_name, uuid, class, window_title, is_tab)
         VALUES (:workspace, :window, :uuid, :class, :window_title, FALSE);" \
        ":workspace" "$workspace_name" \
        ":window" "$window_name" \
        ":uuid" "$uuid" \
        ":class" "$class" \
        ":window_title" "$window_title"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add window '$window_name': $DB_ERROR"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Added window '$window_name' (workspace: '$workspace_name', uuid: '$uuid', class: '$class', window_title: '$window_title')"
    debug_function_exit "$function_name"
}

db_delete_window() {
    local window_name="$1"
    local function_name="db_delete_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    # Delete entry from 'app_windows' table
    db_query \
        "DELETE FROM app_windows WHERE window_name = :window;" \
        ":window" "$window_name"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete window '$window_name': $DB_ERROR"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Deleted window '$window_name'"
    debug_function_exit "$function_name"
}

db_claim_window() {
    local new_workspace_name="$1"
    local new_window_name="$2"
    local uuid="$3"
    local window_title="$4"
    local function_name="db_claim_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$new_workspace_name" "new_workspace_name" || return 1
    validate_parameter_pass "$new_window_name" "new_window_name" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1

    db_query \
        "UPDATE app_windows 
         SET window_name = :window,
             workspace_name = :workspace,
             window_title = :window_title
         WHERE uuid = :uuid;" \
        ":window" "$new_window_name" \
        ":workspace" "$new_workspace_name" \
        ":uuid" "$uuid" \
        ":window_title" "$window_title"

    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to claim window '$new_window_name': $DB_ERROR"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Claimed window '$new_window_name' (workspace: '$new_workspace_name', uuid: '$uuid' window title: '$window_title')"
    debug_function_exit "$function_name"
}

db_add_existing_windows() {
    local window_name=""
    local workspace_name="~workspace"
    local function_name="db_add_existing_windows"

    # Track class counts for unique naming
    local -A class_counts

    # Build class→app_name lookup from applications table
    local -A class_to_app_name
    local map_line=""
    local map_class=""
    local map_name=""
    while IFS= read -r map_line; do
        [[ -z "$map_line" ]] && continue
        map_class="${map_line%%|*}"
        map_name="${map_line#*|}"
        class_to_app_name[$map_class]="$map_name"
    done < <(db_get_class_to_app_name_map)

    debug_function_enter "$function_name"

    # Validate that required global arrays are populated
    validate_global_array_populated CURRENT_UUIDS "CURRENT_UUIDS" || return 1
    validate_global_array_populated CURRENT_CLASSES "CURRENT_CLASSES" || return 1
    validate_global_array_populated CURRENT_TITLES "CURRENT_TITLES" || return 1
    
    debug_log "$function_name" "===== ARRAYS FROM KDOTOOL ====="

    # Build JSON array of window data for batch insert
    local json_rows="["
    local first="true"
    local i=""
    for i in "${!CURRENT_UUIDS[@]}"; do
        local class="${CURRENT_CLASSES[$i]}"
        local uuid="${CURRENT_UUIDS[$i]}"
        local window_title="${CURRENT_TITLES[$i]}"
        
        # Resolve name base: prefer app_name over raw class
        local resolved_app_name=""
        local name_base=""
        if [[ -n "${class_to_app_name[$class]+_}" ]]; then
            resolved_app_name="${class_to_app_name[$class]}"
            name_base="$resolved_app_name"
        else
            name_base="$class"
        fi

        # Increment counter for this name base
        if [[ -z "${class_counts[$name_base]+_}" ]]; then
            class_counts[$name_base]=1
        else
            ((class_counts[$name_base]++))
        fi
        
        # Create unique window name: no suffix for first, -N for subsequent
        if [[ "${class_counts[$name_base]}" -eq 1 ]]; then
            window_name="~${name_base}"
        else
            window_name="~${name_base}-${class_counts[$name_base]}"
        fi

        if [[ "$first" == "true" ]]; then
            first="false"
        else
            json_rows+=","
        fi

        # Escape values for JSON safety
        local json_title=""
        json_title=$(safe_json_value "$window_title")
        local json_class=""
        json_class=$(safe_json_value "$class")
        local json_window_name=""
        json_window_name=$(safe_json_value "$window_name")
        local json_app_name=""
        json_app_name=$(safe_json_value "$resolved_app_name")

        json_rows+="{\"w\":\"$json_window_name\",\"u\":\"$uuid\",\"c\":\"$json_class\",\"t\":\"$json_title\",\"n\":\"$json_app_name\"}"
    done
    json_rows+="]"

    # Single INSERT: batch all windows at once using json_each
    db_query \
        "INSERT OR IGNORE INTO app_windows (workspace_name, window_name, uuid, class, window_title, app_name, is_tab)
         SELECT :workspace,
                json_extract(value, '$.w'),
                json_extract(value, '$.u'),
                json_extract(value, '$.c'),
                json_extract(value, '$.t'),
                CASE WHEN json_extract(value, '$.n') != '' THEN json_extract(value, '$.n') ELSE NULL END,
                FALSE
         FROM json_each(:rows);" \
        ":workspace" "$workspace_name" \
        ":rows" "$json_rows"

    local inserted_count="${DB_RESULT[0]:-0}"
    debug_log "$function_name" "Batch inserted $inserted_count new window(s) out of ${#CURRENT_UUIDS[@]} total"

    debug_function_exit "$function_name"
}

db_delete_stale_windows() {
    local function_name="db_delete_stale_windows"

    debug_function_enter "$function_name"

    # Validate that required global arrays are populated
    validate_global_array_populated CURRENT_UUIDS "CURRENT_UUIDS" || return 1

    # Build JSON array of current UUIDs for single-query delete
    local json_array="["
    local first="true"
    local uuid=""
    for uuid in "${CURRENT_UUIDS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first="false"
        else
            json_array+=","
        fi
        json_array+="\"$uuid\""
    done
    json_array+="]"

    # Single DELETE: remove all tracked windows whose UUID is not in the current set
    db_query \
        "DELETE FROM app_windows
         WHERE uuid IS NOT NULL
         AND uuid NOT IN (SELECT value FROM json_each(:current_uuids));" \
        ":current_uuids" "$json_array"

    local deleted_count="${DB_RESULT[0]:-0}"

    if [[ "$deleted_count" -gt 0 ]]; then
        debug_log "$function_name" "Deleted $deleted_count stale window(s)"
        info_log "$function_name" "Cleaned $deleted_count stale window(s)"
    else
        debug_log "$function_name" "No stale windows to delete"
    fi

    debug_function_exit "$function_name"
}

db_window_exists_by_window_name() {
    local window_name="$1"
    local uuid=""
    local function_name="db_window_exists_by_window_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    # Get UUID by Window Name
    uuid=$(db_get_uuid "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$window_name' ($uuid) already exists."

    debug_function_exit "$function_name"
    echo "$uuid"    
}

db_get_window_name() {
    local uuid="$1"
    local window_name=""
    local function_name="db_get_window_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get Window Name for UUID from 'windows' table
    db_query \
        "SELECT window_name FROM app_windows WHERE uuid = :uuid;" \
        ":uuid" "$uuid"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_WINDOW_NAME_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    window_name="${DB_RESULT[0]}"

    # Pass Window Name
    debug_log "$function_name" "'$uuid' → '$window_name'"

    debug_function_exit "$function_name"
    echo "$window_name"
}

db_get_uuid() {
    local window_name="$1"
    local uuid=""
    local function_name="db_get_uuid"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    # Get UUID for Window Name from 'windows' table
    db_query \
        "SELECT uuid FROM app_windows WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    uuid="${DB_RESULT[0]}"

    # Pass UUID
    debug_log "$function_name" "'$window_name' → '$uuid'"
    
    debug_function_exit "$function_name"
    echo "$uuid"
}

db_get_class() {
    local window_name="$1"
    local class=""
    local function_name="db_get_class"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    # Get Class for Window Name from 'windows' table
    db_query \
        "SELECT class FROM app_windows WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    class="${DB_RESULT[0]}"

    # Pass Class
    debug_log "$function_name" "'$window_name' → '$class'"
    
    debug_function_exit "$function_name"
    echo "$class"
}

db_get_window_title() {
    local window_name="$1"
    local window_title=""
    local function_name="db_get_window_title"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    # Get Window Title for Window Name from 'windows' table
    db_query \
        "SELECT window_title FROM app_windows WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    window_title="${DB_RESULT[0]}"

    # Pass Window Title
    debug_log "$function_name" "'$window_name' → '$window_title'"
    
    debug_function_exit "$function_name"
    echo "$window_title"
}


db_get_tab_by_tab_name() {
    local window_name="$1"
    local tab_name="$2"
    local tab_number=""
    local function_name="db_get_tab_by_tab_name"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$tab_name" "tab_name" || return 1

    # Get Tab Number for Window Name & Tab Name from 'tabs' table
    db_query \
        "SELECT tab_number FROM tabs WHERE window_name = :window_name AND tab_name = :tab_name;" \
        ":window_name" "$window_name" \
        ":tab_name" "$tab_name"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_INVALID_VALUE" "tab not found: $window_name - $tab_name"
        debug_function_exit "$function_name"
        return 1
    fi

    tab_number="${DB_RESULT[0]}"

    # Pass Tab Number
    debug_log "$function_name" "'$window_name' '$tab_name' → '$tab_number'"
    
    debug_function_exit "$function_name"
    echo "$tab_number"
}

db_get_app_metadata_status() {
    local app_id="$1"
    local function_name="db_get_app_metadata_status"
    local result=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    # Single query to check what metadata is already populated
    # Returns pipe-separated: pid_status|title_pattern|display_name|app_class|launch_time_ms|launch_time_samples
    db_query \
        "SELECT
            COALESCE(CAST(supports_pid_validation AS TEXT), ''),
            COALESCE(window_title_pattern, ''),
            COALESCE(display_name, ''),
            COALESCE(app_class, ''),
            COALESCE(CAST(launch_time_ms AS TEXT), '0'),
            COALESCE(CAST(launch_time_samples AS TEXT), '0')
         FROM applications WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    result="${DB_RESULT[0]}"

    debug_log "$function_name" "Metadata status for $app_id: $result"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_post_launch_metadata() {
    local app_id="$1"
    local supports_pid="$2"
    local process_name="$3"
    local executable_path="$4"
    local title_pattern="$5"
    local expected_time="$6"
    local measured_time="$7"
    local function_name="db_set_post_launch_metadata"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1

    # Single UPDATE — empty parameters mean "keep existing value"
    # launch_time_samples increments only when measured_time is provided
    db_query \
        "UPDATE applications SET
            supports_pid_validation = CASE WHEN :supports_pid != '' THEN CAST(:supports_pid AS INTEGER) ELSE supports_pid_validation END,
            process_name = CASE WHEN :process_name != '' THEN :process_name ELSE process_name END,
            executable_path = CASE WHEN :exe_path != '' THEN :exe_path ELSE executable_path END,
            window_title_pattern = CASE WHEN :title_pattern != '' THEN :title_pattern ELSE window_title_pattern END,
            launch_time_ms = CASE WHEN :expected_time != '' THEN CAST(:expected_time AS INTEGER) ELSE launch_time_ms END,
            last_launch_time_ms = CASE WHEN :measured_time != '' THEN CAST(:measured_time AS INTEGER) ELSE last_launch_time_ms END,
            launch_time_samples = CASE WHEN :measured_time != '' THEN COALESCE(launch_time_samples, 0) + 1 ELSE launch_time_samples END
         WHERE app_id = :app_id;" \
        ":app_id" "$app_id" \
        ":supports_pid" "$supports_pid" \
        ":process_name" "$process_name" \
        ":exe_path" "$executable_path" \
        ":title_pattern" "$title_pattern" \
        ":expected_time" "$expected_time" \
        ":measured_time" "$measured_time"

    if [[ "$DB_STATUS" != "OK" ]] || [[ "${DB_RESULT[0]:-0}" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "No rows updated for app_id: $app_id ($DB_ERROR)"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Updated post-launch metadata for $app_id"
    debug_function_exit "$function_name"
    return 0
}

db_release_window_to_auto() {
    local window_name="$1"
    local function_name="db_release_window_to_auto"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    # Step 1: Get class, uuid, window_title, and app_name for this window
    db_query \
        "SELECT class, uuid, window_title, app_name FROM app_windows WHERE window_name = :window_name;" \
        ":window_name" "$window_name"

    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Window not found: $window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    local result=""
    result="${DB_RESULT[0]}"

    local class=""
    local uuid=""
    local window_title=""
    local app_name=""
    class="${result%%|*}"
    result="${result#*|}"
    uuid="${result%%|*}"
    result="${result#*|}"
    window_title="${result%%|*}"
    app_name="${result#*|}"

    # Determine name base: prefer app_name over raw class
    local name_base=""
    if [[ -n "$app_name" ]]; then
        name_base="$app_name"
    else
        name_base="$class"
    fi

    # Step 2: Determine window name — use ~<name_base> if available, otherwise ~<name_base>-N
    local new_window_name=""

    # Check if ~<name_base> (no suffix) already exists
    db_query \
        "SELECT COUNT(*) FROM app_windows
         WHERE workspace_name = '~workspace'
         AND window_name = :exact;" \
        ":exact" "~${name_base}"

    local exact_exists=0
    if [[ ${#DB_RESULT[@]} -gt 0 && "${DB_RESULT[0]:-0}" -gt 0 ]]; then
        exact_exists=1
    fi

    if [[ "$exact_exists" -eq 0 ]]; then
        new_window_name="~${name_base}"
    else
        # Find highest existing counter from ~<name_base>-N pattern
        db_query \
            "SELECT COALESCE(MAX(CAST(SUBSTR(window_name, LENGTH(:prefix) + 1) AS INTEGER)), 1)
             FROM app_windows
             WHERE workspace_name = '~workspace'
             AND window_name LIKE :pattern;" \
            ":prefix" "~${name_base}-" \
            ":pattern" "~${name_base}-%"

        local max_counter=1
        if [[ ${#DB_RESULT[@]} -gt 0 && -n "${DB_RESULT[0]}" ]]; then
            max_counter="${DB_RESULT[0]}"
        fi

        local next_counter=0
        next_counter=$((max_counter + 1))
        new_window_name="~${name_base}-${next_counter}"
    fi

    # Step 3: Reassign the window via db_claim_window
    db_claim_window "~workspace" "$new_window_name" "$uuid" "$window_title"

    debug_log "$function_name" "Released '$window_name' → '$new_window_name' in ~workspace"
    debug_function_exit "$function_name"
}




