#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APPLICATION_REGISTRY_LOADED" || return 0

# shellcheck source=../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../app-definitions/json-parser.sh
source "${LIB_DIR}/app-definitions/json-parser.sh"
# shellcheck source=../app-definitions/validator.sh
source "${LIB_DIR}/app-definitions/validator.sh"
# shellcheck source=../db/app-registry.sh
source "${LIB_DIR}/db/app-registry.sh"
# shellcheck source=app-name.sh
source "${LIB_DIR}/app/app-name.sh"

registry_scan_applications() {
    local function_name="registry_scan_applications"
    local app_count=0

    debug_function_enter "$function_name"

    # Ensure app_name_manual column exists (migration for existing databases)
    db_ensure_app_name_manual_column

    # Load existing manually-set app names (locked during scan)
    local -A manual_names=()
    local _manual_line _manual_id _manual_name
    while IFS= read -r _manual_line; do
        [[ -z "$_manual_line" ]] && continue
        IFS='|' read -r _manual_id _manual_name <<< "$_manual_line"
        [[ -n "$_manual_id" && -n "$_manual_name" ]] && manual_names[$_manual_id]="$_manual_name"
    done < <(db_get_manual_app_names)
    debug_log "$function_name" "Loaded ${#manual_names[@]} manually-set app names"

    # ========================================================================
    # Pass 1: Collect all app metadata into parallel arrays
    # ========================================================================
    local -A processed_apps=()

    # Parallel arrays indexed by scan order
    local -a scan_app_ids=()
    local -a scan_display_names=()
    local -a scan_desktop_files=()
    local -a scan_app_dirs=()
    local -a scan_terminal_cmds=()
    local -a scan_app_classes=()
    local -a scan_launch_modes=()
    local -a scan_title_patterns=()
    local -a scan_has_terminal=()
    local -a scan_has_desktop=()
    local -a scan_supports_pid=()
    local -a scan_process_names=()
    local -a scan_app_names=()
    local -a scan_name_locked=()

    local app_id="" display_name="" desktop_file_path=""
    local app_directory_path="" terminal_command=""
    local app_class="" launch_mode="" window_title_pattern=""
    local has_terminal_launch="" has_desktop_launch=""
    local supports_pid_validation="" process_name="" app_name=""

    for location in "${DESKTOP_FILE_LOCATIONS[@]}"; do
        if [[ ! -d "$location" ]]; then
            debug_log "$function_name" "Skipping non-existent location: $location"
            continue
        fi

        debug_log "$function_name" "Scanning location: $location"

        while IFS= read -r -d '' desktop_file; do
            app_id=$(basename "$desktop_file" .desktop)

            if ! validate_app_id_format "$app_id"; then
                debug_log "$function_name" "Skipping invalid app_id format: $app_id"
                continue
            fi

            if grep -q "^NoDisplay=true" "$desktop_file" 2>/dev/null; then
                debug_log "$function_name" "Skipping (NoDisplay=true): $app_id"
                continue
            fi

            if [[ -v processed_apps[$app_id] ]]; then
                debug_log "$function_name" "Skipping duplicate (already processed): $app_id from $desktop_file"
                continue
            fi

            processed_apps[$app_id]=1

            display_name=$(grep "^Name=" "$desktop_file" | head -1 | cut -d'=' -f2-)
            if [[ -z "$display_name" ]]; then
                debug_log "$function_name" "Warning: No Name field in $desktop_file, using app_id"
                display_name="$app_id"
            fi

            desktop_file_path="$desktop_file"
            has_desktop_launch=true

            # Reset per-app variables
            app_directory_path=""
            terminal_command=""
            app_class=""
            launch_mode=""
            window_title_pattern=""
            has_terminal_launch=false
            supports_pid_validation=""
            process_name=""
            app_name=""

            debug_log "$function_name" "Processing: $app_id ($display_name)"

            # Check for app directory with metadata
            if registry_check_app_files "$app_id" > /dev/null 2>&1; then
                debug_log "$function_name" "Found app definition for: $app_id"

                app_directory_path=$(registry_get_app_directory_path "$app_id")
                local json_file="${app_directory_path}/metadata.json"

                terminal_command=$(json_get_all_metadata "$json_file")

                if [[ -n "$terminal_command" ]]; then
                    has_terminal_launch=true
                    debug_log "$function_name" "Extracted terminal_command: $terminal_command"
                else
                    debug_log "$function_name" "No terminal command found in metadata"
                    has_terminal_launch=false
                fi
            else
                debug_log "$function_name" "No app definition found for: $app_id"
            fi

            # Seed from reference registry for any fields still empty
            local name_locked=false
            if app_registry_exists "$app_id"; then
                local reg_metadata=""
                reg_metadata=$(app_registry_get_metadata "$app_id")

                if [[ -n "$reg_metadata" ]]; then
                    local reg_app_name="" reg_app_class="" reg_window_title=""
                    local reg_launch_mode="" reg_supports_pid="" reg_process_name=""

                    reg_app_name=$(echo "$reg_metadata" | cut -d'|' -f2)
                    reg_app_class=$(echo "$reg_metadata" | cut -d'|' -f3)
                    reg_window_title=$(echo "$reg_metadata" | cut -d'|' -f4)
                    reg_launch_mode=$(echo "$reg_metadata" | cut -d'|' -f5)
                    reg_supports_pid=$(echo "$reg_metadata" | cut -d'|' -f6)
                    reg_process_name=$(echo "$reg_metadata" | cut -d'|' -f7)

                    if [[ -z "$app_name" && -n "$reg_app_name" ]]; then
                        app_name="$reg_app_name"
                        name_locked=true
                    fi
                    [[ -z "$app_class" && -n "$reg_app_class" ]] && app_class="$reg_app_class"
                    [[ -z "$window_title_pattern" && -n "$reg_window_title" ]] && window_title_pattern="$reg_window_title"
                    [[ -z "$launch_mode" && -n "$reg_launch_mode" ]] && launch_mode="$reg_launch_mode"
                    [[ -z "$supports_pid_validation" && -n "$reg_supports_pid" ]] && supports_pid_validation="$reg_supports_pid"
                    [[ -z "$process_name" && -n "$reg_process_name" ]] && process_name="$reg_process_name"

                    debug_log "$function_name" "Seeded from registry: $app_id (class=$app_class, mode=$launch_mode)"
                fi
            fi

            # Check for manually-set app_name (takes highest priority)
            if [[ -v manual_names[$app_id] ]]; then
                app_name="${manual_names[$app_id]}"
                name_locked=true
                debug_log "$function_name" "Using manual app_name: '$app_name' for $app_id"
            fi

            # Auto-generate candidate name if not locked
            if [[ "$name_locked" == "false" ]]; then
                app_name=$(appname_generate "$app_id" "$display_name")
                debug_log "$function_name" "Auto-generated candidate: '$app_name' for $app_id"
            fi

            # Store in parallel arrays
            local idx=${#scan_app_ids[@]}
            scan_app_ids+=("$app_id")
            scan_display_names+=("$display_name")
            scan_desktop_files+=("$desktop_file_path")
            scan_app_dirs+=("$app_directory_path")
            scan_terminal_cmds+=("$terminal_command")
            scan_app_classes+=("$app_class")
            scan_launch_modes+=("$launch_mode")
            scan_title_patterns+=("$window_title_pattern")
            scan_has_terminal+=("$has_terminal_launch")
            scan_has_desktop+=("$has_desktop_launch")
            scan_supports_pid+=("$supports_pid_validation")
            scan_process_names+=("$process_name")
            scan_app_names+=("$app_name")
            scan_name_locked+=("$name_locked")

        done < <(find "$location" -maxdepth 1 -name "*.desktop" \( -type f -o -type l \) -print0 2>/dev/null)
    done

    debug_log "$function_name" "Pass 1 complete: ${#scan_app_ids[@]} apps collected"

    # ========================================================================
    # Pass 2: Deduplicate auto-generated names
    # ========================================================================
    appname_deduplicate scan_app_ids scan_app_names scan_name_locked scan_display_names

    debug_log "$function_name" "Pass 2 complete: names deduplicated"

    # ========================================================================
    # Pass 3: Persist all applications to database
    # ========================================================================
    local i
    for i in "${!scan_app_ids[@]}"; do
        if db_upsert_application_scan \
                "${scan_app_ids[$i]}" "${scan_display_names[$i]}" "${scan_desktop_files[$i]}" \
                "${scan_app_dirs[$i]}" "${scan_terminal_cmds[$i]}" "${scan_app_classes[$i]}" \
                "${scan_has_terminal[$i]}" "${scan_has_desktop[$i]}" \
                "${scan_launch_modes[$i]}" "${scan_title_patterns[$i]}" \
                "${scan_supports_pid[$i]}" "${scan_process_names[$i]}" \
                "${scan_app_names[$i]}"; then
            debug_log "$function_name" "✓ Saved: ${scan_app_ids[$i]} (name=${scan_app_names[$i]})"
            ((app_count++))

            # Store launch options now that the app row exists (FK satisfied)
            if [[ -n "${scan_app_dirs[$i]}" ]]; then
                registry_store_launch_options "${scan_app_ids[$i]}" "${scan_app_dirs[$i]}"
            fi
        else
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to save: ${scan_app_ids[$i]}"
        fi
    done

    # Remove applications no longer installed on the system
    local found_app_ids=""
    found_app_ids=$(printf '%s\n' "${!processed_apps[@]}")
    local removed_count=""
    removed_count=$(db_remove_uninstalled_applications "$found_app_ids")

    echo "" >&3
    print_info "Scan complete: $app_count applications found, $removed_count removed"
    debug_log "$function_name" "Scan complete: $app_count processed, $removed_count removed"
    debug_function_exit "$function_name"

    return 0
}

registry_validate_app_metadata() {
    local app_dir="$1"
    local function_name="registry_validate_app_metadata"
    local json_file=""
    local functions_file=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_dir" "app_dir" || return 1
    validate_directory_exists "$app_dir" || return 1
    
    json_file="${app_dir}/metadata.json"
    functions_file="${app_dir}/functions.sh"
    
    # Extract app_id from directory name for display
    local app_id=""
    app_id=$(basename "$app_dir")
    debug_log "$function_name" "Validating: $app_dir (app_id: $app_id)"
    
    # Validate metadata.json exists
    if [[ ! -f "$json_file" ]]; then
        echo "  ✗ metadata.json not found" >&2
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "metadata.json not found in $app_dir"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate functions.sh exists
    if [[ ! -f "$functions_file" ]]; then
        echo "  ✗ functions.sh not found" >&2
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "functions.sh not found in $app_dir"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate JSON structure
    if ! json_validate_metadata "$json_file"; then
        echo "  ✗ Invalid JSON metadata" >&2
        debug_error "$function_name" "$ERR_INVALID_JSON" "JSON validation failed for $json_file"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate parameters format
    if ! json_validate_parameters "$json_file"; then
        echo "  ✗ Invalid parameter format" >&2
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "Parameter validation failed for $json_file"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate that all functions exist in functions.sh
    local launch_options_count
    launch_options_count=$(json_get_launch_options_count "$json_file")
    
    local i=0
    while [[ $i -lt $launch_options_count ]]; do
        local func_name
        func_name=$(json_get_launch_option_function_name "$json_file" "$i")
        
        if ! json_validate_function_exists "$functions_file" "$func_name"; then
            echo "  ✗ Function not found: $func_name" >&2
            debug_error "$function_name" "$ERR_FUNCTION_NOT_FOUND" "Function $func_name not found in $functions_file"
            debug_function_exit "$function_name"
            return 1
        fi
        
        ((i++))
    done
    
    debug_log "$function_name" "✓ Validation passed for $app_dir"
    debug_function_exit "$function_name"
    return 0
}

registry_validate_all_app_files() {
    local function_name="registry_validate_all_app_files"
    local app_definitions_dir="${LIB_DIR}/app-definitions/apps"
    local total_apps=0
    local valid_apps=0
    local invalid_apps=0
    
    debug_function_enter "$function_name"

    validate_directory_exists "$app_definitions_dir" || return 1
    
    print_info "Validating application definitions in: $app_definitions_dir"
    echo "" >&3
    
    # Iterate through all directories in app-definitions/apps
    for app_dir in "$app_definitions_dir"/*/; do
        # Skip if no directories found (glob doesn't match)
        [[ ! -d "$app_dir" ]] && continue
        
        ((total_apps++))
        local app_id=""
        app_id=$(basename "$app_dir")
        
        print_info "Checking: $app_id"
        
        if registry_validate_app_metadata "$app_dir"; then
            print_success "Valid"
            ((valid_apps++))
        else
            ((invalid_apps++))
        fi
        
        echo "" >&3
    done
    
    # Summary
    print_header "Validation Summary"
    echo "  Total apps:    $total_apps" >&3
    echo "  Valid:         $valid_apps" >&3
    echo "  Invalid:       $invalid_apps" >&3
    
    debug_log "$function_name" "Validation complete: $valid_apps/$total_apps valid"
    debug_function_exit "$function_name"
    
    # Return success only if all apps are valid
    if [[ $invalid_apps -eq 0 && $total_apps -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

registry_check_app_files() {
    local app_id="$1"
    local function_name="registry_check_app_file"
    local app_dir=""
    local json_file=""
    local functions_file=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    app_dir=$(registry_get_app_directory_path "$app_id")
    json_file="${app_dir}/metadata.json"
    functions_file="${app_dir}/functions.sh"
    
    # Check if directory exists with both required files
    if [[ -d "$app_dir" ]] && \
       [[ -f "$json_file" && -r "$json_file" ]] && \
       [[ -f "$functions_file" && -r "$functions_file" ]]; then
        debug_log "$function_name" "Found app directory: $app_dir"
        debug_function_exit "$function_name"
        echo "$app_dir"
        return 0
    else
        debug_log "$function_name" "App directory not found or incomplete: $app_dir"
        debug_function_exit "$function_name"
        return 1
    fi
}

registry_get_app_directory_path() {
    local app_id="$1"
    local function_name="registry_get_app_directory_path"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" "app_id" || return 1
    
    # Return normalized path to app directory
    local app_dir="${LIB_DIR}/app-definitions/apps/${app_id}"
    app_dir=$(realpath "$app_dir")

    debug_log "$function_name" "App directory path: $app_dir"
    debug_function_exit "$function_name"
    echo "$app_dir"
}

registry_store_launch_options() {
    local app_id="$1"
    local app_dir="$2"
    local func_name="registry_store_launch_options"
    local json_file=""
    
    debug_function_enter "$func_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$app_dir" "app_dir" || return 1
    validate_directory_exists "$app_dir" || return 1
    
    json_file="${app_dir}/metadata.json"
    validate_file_exists "$json_file" || return 1
    
    # Clear existing launch options for this app
    db_delete_launch_options_for_app "$app_id"
    
    # Single jq call: get all launch options with inline parameters
    local all_options=""
    all_options=$(json_get_all_launch_options "$json_file")

    if [[ -z "$all_options" ]]; then
        debug_log "$func_name" "No launch options to store for $app_id"
        debug_function_exit "$func_name"
        return 0
    fi

    local order=1
    local options_stored=0
    local function_name=""
    local description=""
    local params_json=""

    while IFS=$'\t' read -r function_name description params_json; do
        [[ -z "$function_name" ]] && continue

        if db_add_launch_option "$app_id" "$function_name" "$description" "$order"; then
            debug_log "$func_name" "Stored launch option: $app_id.$function_name"
            ((options_stored++))

            local option_id=""

            if ! option_id=$(db_get_launch_option_id "$app_id" "$function_name") || [[ -z "$option_id" ]]; then
                debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to retrieve launch option ID for $app_id.$function_name"
            else
                # Parse parameters from JSON blob in a single jq call
                if [[ "$params_json" != "[]" && -n "$params_json" ]]; then
                    local param_lines=""
                    param_lines=$(echo "$params_json" | jq -r '.[] | [.name, .description] | @tsv')

                    local j=0
                    local param_name=""
                    local param_desc=""

                    while IFS=$'\t' read -r param_name param_desc; do
                        [[ -z "$param_name" ]] && continue

                        if db_add_launch_parameter "$app_id" "$option_id" "$param_name" "$param_desc" "$j"; then
                            debug_log "$func_name" "Stored parameter: $app_id.$function_name.$param_name"
                        else
                            debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to store parameter: $app_id.$function_name.$param_name"
                        fi

                        ((j++))
                    done <<< "$param_lines"
                fi
            fi

            ((order++))
        else
            debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to store launch option: $app_id.$function_name"
        fi
    done <<< "$all_options"
    
    debug_log "$func_name" "Stored $options_stored launch options for $app_id"
    debug_function_exit "$func_name"
    return 0
}


