#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APPLICATION_REGISTRY_LOADED" || return 0

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

registry_scan_applications() {
    local function_name="registry_scan_applications"
    local app_count=0
    local app_id=""
    local display_name=""
    local desktop_file_path=""
    local app_directory_path=""
    local terminal_command=""
    local app_class=""
    local launch_mode=""
    local window_title_pattern=""
    local has_terminal_launch=false
    local has_desktop_launch=false
    local supports_pid_validation=""
    local process_name=""
    
    debug_function_enter "$function_name"
    
    # Track processed app_ids to handle duplicates (prefer user local > system)
    local -A processed_apps
    
    # Iterate through desktop file locations in reverse priority order
    # (process system locations first, so user local overrides them)
    for location in "${DESKTOP_FILE_LOCATIONS[@]}"; do
        if [[ ! -d "$location" ]]; then
            debug_log "$function_name" "Skipping non-existent location: $location"
            continue
        fi
        
        debug_log "$function_name" "Scanning location: $location"
        
        # Find all .desktop files in this location
        while IFS= read -r -d '' desktop_file; do
            # Extract app_id from filename (basename without .desktop)
            app_id=$(basename "$desktop_file" .desktop)
            
            # Validate app_id format (reject malicious .desktop filenames)
            if ! validate_app_id_format "$app_id"; then
                debug_log "$function_name" "Skipping invalid app_id format: $app_id"
                continue
            fi

            # Skip if NoDisplay=true
            if grep -q "^NoDisplay=true" "$desktop_file" 2>/dev/null; then
                debug_log "$function_name" "Skipping (NoDisplay=true): $app_id"
                continue
            fi
            
            # Check if we've already processed this app_id
            if [[ -v processed_apps[$app_id] ]]; then
                debug_log "$function_name" "Skipping duplicate (already processed): $app_id from $desktop_file"
                continue
            fi
            
            # Mark as processed
            processed_apps[$app_id]=1
            
            # Extract display name from .desktop file
            display_name=$(grep "^Name=" "$desktop_file" | head -1 | cut -d'=' -f2-)
            if [[ -z "$display_name" ]]; then
                debug_log "$function_name" "Warning: No Name field in $desktop_file, using app_id"
                display_name="$app_id"
            fi
            
            desktop_file_path="$desktop_file"
            has_desktop_launch=true
            
            # Reset app file variables
            app_directory_path=""
            terminal_command=""
            app_class=""
            launch_mode=""
            window_title_pattern=""
            has_terminal_launch=false
            supports_pid_validation=""
            process_name=""
            
            debug_log "$function_name" "Processing: $app_id ($display_name)"
            
            # Check for app directory with metadata
            if registry_check_app_files "$app_id" > /dev/null 2>&1; then
                debug_log "$function_name" "Found app definition for: $app_id"
                
                app_directory_path=$(registry_get_app_directory_path "$app_id")
                local json_file="${app_directory_path}/metadata.json"
                
                # Extract terminal command from JSON
                terminal_command=$(json_get_terminal_command "$json_file")
                
                # Extract app_class from JSON
                app_class=$(json_get_app_class "$json_file")
                
                # Extract and resolve launch_mode from JSON
                local launch_mode_constant=""
                launch_mode_constant=$(json_get_launch_mode "$json_file")
                if [[ -n "$launch_mode_constant" ]]; then
                    # Resolve constant name (e.g., LAUNCH_MODE_UNIQUE) to value (e.g., unique)
                    launch_mode="${!launch_mode_constant}"
                fi
                
                # Extract window_title_pattern from JSON
                window_title_pattern=$(json_get_window_title_pattern "$json_file")
                
                if [[ -n "$terminal_command" ]]; then
                    has_terminal_launch=true
                    debug_log "$function_name" "Extracted terminal_command: $terminal_command"
                    
                    # Store launch options in database
                    registry_store_launch_options "$app_id" "$app_directory_path"
                else
                    debug_log "$function_name" "No terminal command found in metadata"
                    has_terminal_launch=false
                fi
            else
                debug_log "$function_name" "No app definition found for: $app_id"
            fi
            
            # Seed from reference registry for any fields still empty
            if app_registry_exists "$app_id"; then
                local reg_metadata=""
                reg_metadata=$(app_registry_get_metadata "$app_id")

                if [[ -n "$reg_metadata" ]]; then
                    local reg_app_class=""
                    local reg_window_title=""
                    local reg_launch_mode=""
                    local reg_supports_pid=""
                    local reg_process_name=""

                    reg_app_class=$(echo "$reg_metadata" | cut -d'|' -f2)
                    reg_window_title=$(echo "$reg_metadata" | cut -d'|' -f3)
                    reg_launch_mode=$(echo "$reg_metadata" | cut -d'|' -f4)
                    reg_supports_pid=$(echo "$reg_metadata" | cut -d'|' -f5)
                    reg_process_name=$(echo "$reg_metadata" | cut -d'|' -f6)

                    [[ -z "$app_class" && -n "$reg_app_class" ]] && app_class="$reg_app_class"
                    [[ -z "$window_title_pattern" && -n "$reg_window_title" ]] && window_title_pattern="$reg_window_title"
                    [[ -z "$launch_mode" && -n "$reg_launch_mode" ]] && launch_mode="$reg_launch_mode"
                    [[ -z "$supports_pid_validation" && -n "$reg_supports_pid" ]] && supports_pid_validation="$reg_supports_pid"
                    [[ -z "$process_name" && -n "$reg_process_name" ]] && process_name="$reg_process_name"

                    debug_log "$function_name" "Seeded from registry: $app_id (class=$app_class, mode=$launch_mode)"
                fi
            fi
            
            # Add application to database with all metadata
            if db_add_application "$app_id" "$display_name" "$desktop_file_path" \
                                  "$app_directory_path" "$terminal_command" "$app_class" \
                                  "$has_terminal_launch" "$has_desktop_launch"; then
                debug_log "$function_name" "✓ Saved to database: $app_id (terminal: $has_terminal_launch, desktop: $has_desktop_launch)"
                ((app_count++))
                
                # Set launch mode if extracted from metadata
                if [[ -n "$launch_mode" ]]; then
                    db_set_launch_mode "$app_id" "$launch_mode"
                fi
                
                # Set window title pattern if extracted from metadata
                if [[ -n "$window_title_pattern" ]]; then
                    db_set_window_title_pattern "$app_id" "$window_title_pattern"
                fi
                
                # Set PID validation data if seeded from registry
                if [[ -n "$supports_pid_validation" && -n "$process_name" ]]; then
                    local pid_support=""
                    if [[ "$supports_pid_validation" -eq 1 ]]; then
                        pid_support="true"
                    else
                        pid_support="false"
                    fi
                    db_set_pid_validation_data "$app_id" "$pid_support" "$process_name" ""
                fi
            else
                debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to save application: $app_id"
            fi
            
        done < <(find "$location" -maxdepth 1 -name "*.desktop" -type f -print0 2>/dev/null)
    done
    
    echo "" >&3
    echo "Scan complete: $app_count applications added to registry" >&3
    debug_log "$function_name" "Scan complete: $app_count applications processed"
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
    
    echo "Validating application definitions in: $app_definitions_dir" >&3
    echo "" >&3
    
    # Iterate through all directories in app-definitions/apps
    for app_dir in "$app_definitions_dir"/*/; do
        # Skip if no directories found (glob doesn't match)
        [[ ! -d "$app_dir" ]] && continue
        
        ((total_apps++))
        local app_id=""
        app_id=$(basename "$app_dir")
        
        echo "Checking: $app_id" >&3
        
        if registry_validate_app_metadata "$app_dir"; then
            echo "  ✓ Valid" >&3
            ((valid_apps++))
        else
            ((invalid_apps++))
        fi
        
        echo "" >&3
    done
    
    # Summary
    echo "================================" >&3
    echo "Validation Summary:" >&3
    echo "  Total apps:    $total_apps" >&3
    echo "  Valid:         $valid_apps" >&3
    echo "  Invalid:       $invalid_apps" >&3
    echo "================================" >&3
    
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
    local launch_options_count=0
    
    debug_function_enter "$func_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$app_dir" "app_dir" || return 1
    validate_directory_exists "$app_dir" || return 1
    
    json_file="${app_dir}/metadata.json"
    validate_file_exists "$json_file" || return 1
    
    # Clear existing launch options for this app
    db_delete_launch_options_for_app "$app_id"
    
    # Get count of launch options
    launch_options_count=$(json_get_launch_options_count "$json_file")
    
    if [[ $launch_options_count -eq 0 ]]; then
        debug_log "$func_name" "No launch options to store for $app_id"
        debug_function_exit "$func_name"
        return 0
    fi
    
    # Parse JSON and store launch options
    local order=1
    local options_stored=0
    local i=0
    
    while [[ $i -lt $launch_options_count ]]; do
        local function_name=""
        local description=""
        
        function_name=$(json_get_launch_option_function_name "$json_file" "$i")
        description=$(json_get_launch_option_description "$json_file" "$i")
        
        if db_add_launch_option "$app_id" "$function_name" "$description" "$order"; then
            debug_log "$func_name" "Stored launch option: $app_id.$function_name"
            ((options_stored++))

            # Get the ID of the launch option we just added
            local option_id=""
            option_id=$(db_get_launch_option_id "$app_id" "$function_name")
            
            if [[ $? -ne 0 || -z "$option_id" ]]; then
                debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to retrieve launch option ID for $app_id.$function_name"
            else
                # Store parameters for this launch option
                local parameters=""
                parameters=$(json_get_launch_option_parameters "$json_file" "$i")
                
                if [[ "$parameters" != "[]" && "$parameters" != "null" ]]; then
                    local param_count=""
                    param_count=$(echo "$parameters" | jq 'length')
                    
                    local j=0
                    while [[ $j -lt $param_count ]]; do
                        local param_name=""
                        local param_desc=""
                        
                        param_name=$(echo "$parameters" | jq -r ".[$j].name")
                        param_desc=$(echo "$parameters" | jq -r ".[$j].description")
                        
                        if db_add_launch_parameter "$app_id" "$option_id" "$param_name" "$param_desc" "$j"; then
                            debug_log "$func_name" "Stored parameter: $app_id.$function_name.$param_name"
                        else
                            debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to store parameter: $app_id.$function_name.$param_name"
                        fi
                        
                        ((j++))
                    done
                fi
            fi
            
            ((order++))
        else
            debug_error "$func_name" "$ERR_DATABASE_ERROR" "Failed to store launch option: $app_id.$function_name"
        fi
        
        ((i++))
    done
    
    debug_log "$func_name" "Stored $options_stored launch options for $app_id"
    debug_function_exit "$func_name"
    return 0
}


