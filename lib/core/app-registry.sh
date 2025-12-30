#!/bin/bash

# lib/core/application-registry.sh
# Application registry management - scanning, validation, and query functions
#
# This module scans the system for available applications, validates their 
# launch capabilities, and provides query functions for the application registry.
# 
# Database operations are handled by calling functions in lib/core/database.sh
#
# Dependencies:
# - lib/core/common.sh (LAUNCH_TYPE_* constants)
# - lib/core/database.sh (db_* functions)
# - lib/utils/debug.sh (debug logging)

check_and_set_guard "_KDOITALL_APPLICATION_REGISTRY_LOADED" || return 0

# Standard .desktop file locations
readonly DESKTOP_FILE_LOCATIONS=(
    "/usr/share/applications"
    "/usr/local/share/applications"
    "$HOME/.local/share/applications"
)

# ============================================================================
# Metadata Validation
# ============================================================================

registry_validate_app_metadata() {
    local app_file_path="$1"
    local function_name="registry_validate_app_metadata"
    local validation_output=""
    local app_id_from_file=""
    local expected_app_id=""
    local errors=0
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_file_path" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Verify file exists
    if [[ ! -f "$app_file_path" ]]; then
        debug_error "$function_name" "$ERR_APP_FILE_NOT_FOUND" "$app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Extract expected app_id from filename
    expected_app_id=$(basename "$app_file_path" .sh)
    debug_log "$function_name" "Validating: $app_file_path (expected app_id: $expected_app_id)"
    
    # Source file in subshell to extract variables
    validation_output=$(
        (
            set +e
            # shellcheck disable=SC1090
            source "$app_file_path" 2>/dev/null || exit 1
            
            # Check for required variables
            [[ -z "${APP_ID:-}" ]] && echo "ERROR:APP_ID is missing"
            [[ -z "${APP_CLASS:-}" ]] && echo "ERROR:APP_CLASS is missing"
            [[ -z "${TERMINAL_COMMAND:-}" ]] && echo "ERROR:TERMINAL_COMMAND is missing"
            
            # Check if LAUNCH_OPTIONS exists and is not empty
            if [[ ! -v LAUNCH_OPTIONS ]]; then
                echo "ERROR:LAUNCH_OPTIONS array is missing"
            elif [[ ${#LAUNCH_OPTIONS[@]} -eq 0 ]]; then
                echo "ERROR:LAUNCH_OPTIONS array is empty"
            fi
            
            # Output values for further validation
            echo "APP_ID=${APP_ID:-}"
            echo "APP_CLASS=${APP_CLASS:-}"
            echo "TERMINAL_COMMAND=${TERMINAL_COMMAND:-}"
            echo "LAUNCH_OPTIONS_COUNT=${#LAUNCH_OPTIONS[@]}"
        ) 2>&1
    )
    
    # Parse validation output
    while IFS= read -r line; do
        if [[ "$line" =~ ^ERROR:(.*)$ ]]; then
            echo "  ✗ ${BASH_REMATCH[1]}"
            ((errors++))
        elif [[ "$line" =~ ^APP_ID=(.*)$ ]]; then
            app_id_from_file="${BASH_REMATCH[1]}"
        fi
    done <<< "$validation_output"
    
    # Validate APP_ID matches filename
    if [[ -n "$app_id_from_file" && "$app_id_from_file" != "$expected_app_id" ]]; then
        echo "  ✗ APP_ID mismatch: file has '$app_id_from_file' but filename suggests '$expected_app_id'"
        ((errors++))
    fi
    
    # Report results
    if [[ $errors -eq 0 ]]; then
        debug_log "$function_name" "✓ Validation passed for $app_file_path"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "$app_file_path ($errors errors)"
        debug_function_exit "$function_name"
        return 1
    fi
}

registry_validate_all_app_files() {
    local function_name="registry_validate_all_app_files"
    local app_dir="${LIB_DIR}/applications"
    local total_files=0
    local valid_files=0
    local invalid_files=0
    
    debug_function_enter "$function_name"
    
    # Check if applications directory exists
    if [[ ! -d "$app_dir" ]]; then
        echo "Error: Applications directory not found: $app_dir"
        debug_error "$function_name" "$ERR_DIRECTORY_NOT_FOUND" "$app_dir"
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "Validating application files in: $app_dir"
    echo ""
    
    # Iterate through all .sh files
    for app_file in "$app_dir"/*.sh; do
        # Skip if no files found (glob doesn't match)
        [[ ! -f "$app_file" ]] && continue
        
        ((total_files++))
        local app_name=""
        app_name=$(basename "$app_file")
        
        echo "Checking: $app_name"
        
        if registry_validate_app_metadata "$app_file"; then
            echo "  ✓ Valid"
            ((valid_files++))
        else
            ((invalid_files++))
        fi
        
        echo ""
    done
    
    # Summary
    echo "================================"
    echo "Validation Summary:"
    echo "  Total files:   $total_files"
    echo "  Valid:         $valid_files"
    echo "  Invalid:       $invalid_files"
    echo "================================"
    
    debug_log "$function_name" "Validation complete: $valid_files/$total_files valid"
    debug_function_exit "$function_name"
    
    # Return success only if all files are valid
    if [[ $invalid_files -eq 0 && $total_files -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Main Scanning Function
# ============================================================================

registry_scan_applications() {
    local function_name="registry_scan_applications"
    local app_count=0
    local app_id=""
    local display_name=""
    local desktop_file_path=""
    local has_terminal_launch=false
    local has_desktop_launch=false
    local terminal_command=""
    local app_file_path=""
    
    debug_function_enter "$function_name"
    
    # Track processed app_ids to handle duplicates (prefer user local > system)
    declare -A processed_apps
    
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
            
            debug_log "$function_name" "Processing: $app_id ($display_name)"
            
            # Check for app file
            app_file_path=$(registry_check_app_file "$app_id")
            if [[ -n "$app_file_path" ]]; then
                debug_log "$function_name" "Found app file: $app_file_path"
                
                # Parse app file to extract metadata
                if registry_parse_app_file "$app_file_path"; then
                    # Parse successful - metadata extraction will call db functions
                    has_terminal_launch=true
                else
                    debug_error "$function_name" "$ERR_APP_FILE_PARSE_FAILED" "$app_id"
                    has_terminal_launch=false
                fi
            else
                debug_log "$function_name" "No app file found for: $app_id"
                has_terminal_launch=false
                app_file_path=""
            fi
            
            # Add application to database
            # TODO: Call db_add_application() once it's implemented
            # db_add_application "$app_id" "$display_name" "$desktop_file_path" \
            #                    "$has_terminal_launch" "$has_desktop_launch" \
            #                    "$terminal_command" "$app_file_path"
            
            debug_log "$function_name" "Added: $app_id (terminal: $has_terminal_launch, desktop: $has_desktop_launch)"
            ((app_count++))
            
        done < <(find "$location" -maxdepth 1 -name "*.desktop" -type f -print0 2>/dev/null)
    done
    
    debug_log "$function_name" "Scan complete: $app_count applications processed"
    debug_function_exit "$function_name"
    
    return 0
}

# ============================================================================
# App File Detection
# ============================================================================

registry_check_app_file() {
    local app_id="$1"
    local function_name="registry_check_app_file"
    local app_file_path=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Construct expected path using LIB_DIR
    app_file_path="${LIB_DIR}/applications/${app_id}.sh"
    
    # Check if file exists and is readable
    if [[ -f "$app_file_path" && -r "$app_file_path" ]]; then
        debug_log "$function_name" "Found app file: $app_file_path"
        debug_function_exit "$function_name"
        echo "$app_file_path"
        return 0
    else
        debug_log "$function_name" "App file not found: $app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ============================================================================
# Terminal Command Validation
# ============================================================================

registry_validate_terminal_command() {
    local app_id="$1"
    local terminal_command="$2"
    local function_name="registry_validate_terminal_command"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameters
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if [[ -z "$terminal_command" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "terminal_command"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Checking command availability: $terminal_command"
    
    # Check if command exists using 'command -v'
    if command -v "$terminal_command" &> /dev/null; then
        debug_log "$function_name" "Command available: $terminal_command"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Command not available: $terminal_command"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ============================================================================
# App File Parsing
# ============================================================================

registry_parse_app_file() {
    local app_file_path="$1"
    local function_name="registry_parse_app_file"
    local parsed_app_id=""
    local parsed_app_class=""
    local parsed_terminal_command=""
    local parse_output=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_file_path" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Verify file exists
    if [[ ! -f "$app_file_path" ]]; then
        debug_error "$function_name" "$ERR_APP_FILE_NOT_FOUND" "$app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Parsing app file: $app_file_path"
    
    # Source the app file in a subshell to extract metadata
    # Redirect function definitions to /dev/null to prevent execution
    parse_output=$(
        (
            # Prevent functions from being executed during sourcing
            set +e
            # Source the file to load variables
            # shellcheck disable=SC1090
            source "$app_file_path" 2>/dev/null || exit 1
            
            # Output metadata variables
            echo "APP_ID=${APP_ID:-}"
            echo "APP_CLASS=${APP_CLASS:-}"
            echo "TERMINAL_COMMAND=${TERMINAL_COMMAND:-}"
            
            # Output launch options if they exist
            if [[ -v LAUNCH_OPTIONS ]]; then
                for func_name in "${!LAUNCH_OPTIONS[@]}"; do
                    echo "LAUNCH_OPTION:${func_name}=${LAUNCH_OPTIONS[$func_name]}"
                done
            fi
        ) 2>&1
    )
    
    # Check if parsing was successful
    if [[ -z "$parse_output" ]]; then
        debug_error "$function_name" "$ERR_APP_FILE_PARSE_FAILED" "$app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Extract metadata from parse output
    while IFS= read -r line; do
        if [[ "$line" =~ ^APP_ID=(.*)$ ]]; then
            parsed_app_id="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^APP_CLASS=(.*)$ ]]; then
            parsed_app_class="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^TERMINAL_COMMAND=(.*)$ ]]; then
            parsed_terminal_command="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^LAUNCH_OPTION:([^=]+)=(.*)$ ]]; then
            local func_name="${BASH_REMATCH[1]}"
            local display_name="${BASH_REMATCH[2]}"
            
            debug_log "$function_name" "Found launch option: $func_name -> $display_name"
            
            # TODO: Call db_add_launch_option() once it's implemented
            # db_add_launch_option "$parsed_app_id" "$func_name" "$display_name"
        fi
    done <<< "$parse_output"
    
    # Validate that required metadata was found
    if [[ -z "$parsed_app_id" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "APP_ID missing in $app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if [[ -z "$parsed_app_class" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "APP_CLASS missing in $app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if [[ -z "$parsed_terminal_command" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "TERMINAL_COMMAND missing in $app_file_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Successfully parsed: APP_ID=$parsed_app_id, APP_CLASS=$parsed_app_class"
    debug_log "$function_name" "TERMINAL_COMMAND=$parsed_terminal_command"
    
    debug_function_exit "$function_name"
    return 0
}

# ============================================================================
# Query Functions
# ============================================================================

registry_get_application_info() {
    local app_id="$1"
    local function_name="registry_get_application_info"
    local app_info=""
    local launch_options=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Retrieving info for: $app_id"
    
    # TODO: Get application details from database
    # app_info=$(db_get_application "$app_id")
    # if [[ $? -ne 0 ]]; then
    #     debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
    #     debug_function_exit "$function_name"
    #     return 1
    # fi
    
    # TODO: Get launch options from database
    # launch_options=$(db_get_launch_options "$app_id")
    
    # Format output (this will be replaced with actual data from db functions)
    echo "Application: [Display Name] ($app_id)"
    echo "Desktop File: [desktop_file_path]"
    echo "Terminal Launch: [Available/Not Available] (terminal_command)"
    echo "Desktop Launch: [Available/Not Available]"
    echo "App File: [app_file_path or N/A]"
    echo ""
    echo "Launch Options:"
    echo "  [List from db_get_launch_options]"
    
    debug_function_exit "$function_name"
    return 0
}

registry_list_applications() {
    local filter="${1:-all}"
    local function_name="registry_list_applications"
    local app_list=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate filter parameter
    case "$filter" in
        all|terminal|desktop|both)
            debug_log "$function_name" "Filter: $filter"
            ;;
        *)
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid filter: $filter (must be: all, terminal, desktop, both)"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # TODO: Get filtered application list from database
    # app_list=$(db_list_applications "$filter")
    # if [[ $? -ne 0 ]]; then
    #     debug_error "$function_name" "$ERR_NO_DESKTOP_FILES_FOUND" "No applications found"
    #     debug_function_exit "$function_name"
    #     return 1
    # fi
    
    # Format output header
    echo "Available Applications:"
    printf "%-30s %-25s %-9s %-8s %-7s\n" "NAME" "APP_ID" "TERMINAL" "DESKTOP" "OPTIONS"
    printf "%-30s %-25s %-9s %-8s %-7s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..25})" "$(printf '%.0s-' {1..9})" "$(printf '%.0s-' {1..8})" "$(printf '%.0s-' {1..7})"
    
    # TODO: Parse and display results from db_list_applications
    # Format each row:
    # printf "%-30s %-25s %-9s %-8s %-7s\n" "$display_name" "$app_id" "$terminal_status" "$desktop_status" "$option_count"
    # Where:
    #   terminal_status = "✓" if has_terminal_launch, "✗" otherwise
    #   desktop_status = "✓" if has_desktop_launch, "✗" otherwise
    #   option_count = number of launch options
    
    echo "[Data will be populated by db_list_applications]"
    
    debug_function_exit "$function_name"
    return 0
}

registry_get_launch_options() {
    local app_id="$1"
    local function_name="registry_get_launch_options"
    local launch_options=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Retrieving launch options for: $app_id"
    
    # TODO: Get launch options from database
    # launch_options=$(db_get_launch_options "$app_id")
    # if [[ $? -ne 0 ]]; then
    #     debug_log "$function_name" "No launch options found for: $app_id"
    #     echo "No launch options available for: $app_id"
    #     debug_function_exit "$function_name"
    #     return 1
    # fi
    
    # Format output
    echo "Launch options for $app_id:"
    
    # TODO: Parse and display results from db_get_launch_options
    # Format each option:
    # echo "  $index) $function_name - $description"
    # Example:
    #   1) launch_vscode_window - Open directory or file
    #   2) launch_vscode_workspace_window - Open .code-workspace file
    
    echo "  [Data will be populated by db_get_launch_options]"
    
    debug_function_exit "$function_name"
    return 0
}