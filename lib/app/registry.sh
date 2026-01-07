#!/bin/bash

check_and_set_guard "_KDOITALL_APPLICATION_REGISTRY_LOADED" || return 0

# shellcheck source=../db/app-registry.sh
source "${LIB_DIR}/db/app-registry.sh"
# shellcheck source=../db/app-registry.sh
source "${LIB_DIR}/db/launch-options.sh"

# Standard .desktop file locations
readonly DESKTOP_FILE_LOCATIONS=(
    "/usr/share/applications"
    "/usr/local/share/applications"
    "$HOME/.local/share/applications"
)

registry_validate_app_metadata() {
    local app_file_path="$1"
    local function_name="registry_validate_app_metadata"
    local validation_output=""
    local errors=0
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_file_path" || return 1
    validate_file_exists "$app_file_path" || return 1
    
    # Extract app_id from filename for display
    local app_id=""
    app_id=$(basename "$app_file_path" .sh)
    debug_log "$function_name" "Validating: $app_file_path (app_id: $app_id)"
    
    # Source file in subshell to extract variables
    validation_output=$(
        (
            set +e
            # shellcheck disable=SC1090
            source "$app_file_path" 2>/dev/null || exit 1
            
            # Check for required variables
            [[ -z "${TERMINAL_COMMAND:-}" ]] && echo "ERROR:TERMINAL_COMMAND is missing"
            
            # Check if LAUNCH_OPTIONS exists and is not empty
            if [[ ! -v LAUNCH_OPTIONS ]]; then
                echo "ERROR:LAUNCH_OPTIONS array is missing"
            elif [[ ${#LAUNCH_OPTIONS[@]} -eq 0 ]]; then
                echo "ERROR:LAUNCH_OPTIONS array is empty"
            fi
            
            # Output values for logging
            echo "TERMINAL_COMMAND=${TERMINAL_COMMAND:-}"
            echo "LAUNCH_OPTIONS_COUNT=${#LAUNCH_OPTIONS[@]}"
        ) 2>&1
    )
    
    # Parse validation output
    while IFS= read -r line; do
        if [[ "$line" =~ ^ERROR:(.*)$ ]]; then
            echo "  ✗ ${BASH_REMATCH[1]}"
            ((errors++))
        fi
    done <<< "$validation_output"
    
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
    local app_dir="${LIB_DIR}/launchers"
    local total_files=0
    local valid_files=0
    local invalid_files=0
    
    debug_function_enter "$function_name"

    validate_directory_exists "$app_dir" || return 1
    
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

registry_scan_applications() {
    local function_name="registry_scan_applications"
    local app_count=0
    local app_id=""
    local display_name=""
    local desktop_file_path=""
    local app_file_path=""
    local terminal_command=""
    local has_terminal_launch=false
    local has_desktop_launch=false
    
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
            
            # Reset app file variables
            app_file_path=""
            terminal_command=""
            has_terminal_launch=false
            
            debug_log "$function_name" "Processing: $app_id ($display_name)"
            
            # Check for app file
            if registry_check_app_file "$app_id" > /dev/null 2>&1; then
                debug_log "$function_name" "Found app file for: $app_id"
                
                app_file_path=$(registry_get_app_file_path "$app_id")
                
                # Extract terminal command
                terminal_command=$(registry_extract_terminal_command "$app_file_path")
                
                if [[ -n "$terminal_command" ]]; then
                    has_terminal_launch=true
                    debug_log "$function_name" "Extracted terminal_command: $terminal_command"
                    
                    # Store launch options in database
                    registry_store_launch_options "$app_id" "$app_file_path"
                else
                    debug_log "$function_name" "No terminal command found in app file"
                    has_terminal_launch=false
                fi
            else
                debug_log "$function_name" "No app file found for: $app_id"
            fi
            
            # Add application to database with all metadata
            if db_add_application "$app_id" "$display_name" "$desktop_file_path" \
                                  "$app_file_path" "$terminal_command" "" \
                                  "$has_terminal_launch" "$has_desktop_launch"; then
                debug_log "$function_name" "✓ Saved to database: $app_id (terminal: $has_terminal_launch, desktop: $has_desktop_launch)"
                ((app_count++))
            else
                debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to save application: $app_id"
            fi
            
        done < <(find "$location" -maxdepth 1 -name "*.desktop" -type f -print0 2>/dev/null)
    done
    
    echo ""
    echo "Scan complete: $app_count applications added to registry"
    debug_log "$function_name" "Scan complete: $app_count applications processed"
    debug_function_exit "$function_name"
    
    return 0
}

registry_get_app_file_path() {
    local app_id="$1"
    
    if [[ -z "$app_id" ]]; then
        return 1
    fi
    
    echo "${LIB_DIR}/launchers/${app_id}.sh"
    return 0
}

registry_check_app_file() {
    local app_id="$1"
    local function_name="registry_check_app_file"
    local app_file_path=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    
    app_file_path=$(registry_get_app_file_path "$app_id")
    
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

registry_validate_terminal_command() {
    local app_id="$1"
    local terminal_command="$2"
    local function_name="registry_validate_terminal_command"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$terminal_command" || return 1
    
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

registry_extract_terminal_command() {
    local app_file_path="$1"
    local function_name="registry_extract_terminal_command"
    local terminal_command=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$app_file_path" || return 1
    validate_file_exists "$app_file_path" || return 1
    
    # Source file in subshell and extract TERMINAL_COMMAND
    terminal_command=$(
        (
            set +e
            # shellcheck disable=SC1090
            source "$app_file_path" 2>/dev/null || exit 1
            echo "${TERMINAL_COMMAND:-}"
        ) 2>&1
    )
    
    debug_log "$function_name" "Extracted terminal_command: ${terminal_command:-NULL}"
    debug_function_exit "$function_name"
    echo "$terminal_command"
    return 0
}

registry_store_launch_options() {
    local app_id="$1"
    local app_file_path="$2"
    local function_name="registry_store_launch_options"
    local parse_output=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$app_file_path" || return 1
    validate_file_exists "$app_file_path" || return 1
    
    # Clear existing launch options for this app
    db_delete_launch_options_for_app "$app_id"
    
    # Parse launch options from app file
    parse_output=$(
        (
            set +e
            # shellcheck disable=SC1090
            source "$app_file_path" 2>/dev/null || exit 1
            
            # Check if LAUNCH_OPTIONS exists
            if [[ -v LAUNCH_OPTIONS ]]; then
                local order=1
                for func_name in "${!LAUNCH_OPTIONS[@]}"; do
                    echo "LAUNCH_OPTION:${order}:${func_name}:${LAUNCH_OPTIONS[$func_name]}"
                    ((order++))
                done
            fi
        ) 2>&1
    )
    
    # Store each launch option in database
    local options_stored=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^LAUNCH_OPTION:([0-9]+):([^:]+):(.*)$ ]]; then
            local order="${BASH_REMATCH[1]}"
            local func_name="${BASH_REMATCH[2]}"
            local description="${BASH_REMATCH[3]}"
            
            if db_add_launch_option "$app_id" "$func_name" "$description" "$order"; then
                debug_log "$function_name" "Stored launch option: $app_id.$func_name"
                ((options_stored++))
            else
                debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to store launch option: $app_id.$func_name"
            fi
        fi
    done <<< "$parse_output"
    
    debug_log "$function_name" "Stored $options_stored launch options for $app_id"
    debug_function_exit "$function_name"
    return 0
}

registry_parse_app_file() {
    local app_file_path="$1"
    local function_name="registry_parse_app_file"
    local parsed_app_id=""
    local parsed_app_class=""
    local parsed_terminal_command=""
    local parse_output=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_file_path" || return 1
    validate_file_exists "$app_file_path" || return 1
    
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
    
    validate_app_metadata "$app_file_path" "$parsed_app_id" "APP_ID" || return 1
    validate_app_metadata "$app_file_path" "$parsed_app_class" "APP_CLASS" || return 1
    validate_app_metadata "$app_file_path" "$parsed_terminal_command" "TERMINAL_COMMAND" || return 1
    
    debug_log "$function_name" "Successfully parsed: APP_ID=$parsed_app_id, APP_CLASS=$parsed_app_class"
    debug_log "$function_name" "TERMINAL_COMMAND=$parsed_terminal_command"
    
    debug_function_exit "$function_name"
    return 0
}

registry_get_application_info() {
    local app_id="$1"
    local function_name="registry_get_application_info"
    local app_info=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    
    debug_log "$function_name" "Retrieving info for: $app_id"
    
    # Get application details from database
    app_info=$(db_get_application "$app_id")
    if [[ $? -ne 0 ]]; then
        echo "Error: Application not found: $app_id"
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Parse the pipe-delimited output
    # Format: app_id|display_name|desktop_file_path|app_file_path|terminal_command|app_class|has_terminal|has_desktop|last_validated
    IFS='|' read -r _ display_name desktop_file_path \
        app_file_path terminal_command app_class \
        has_terminal has_desktop last_validated <<< "$app_info"
    
    # Convert boolean values for display
    local terminal_status="Not Available"
    [[ "$has_terminal" == "1" || "$has_terminal" == "TRUE" ]] && terminal_status="Available"
    
    local desktop_status="Not Available"
    [[ "$has_desktop" == "1" || "$has_desktop" == "TRUE" ]] && desktop_status="Available"
    
    # Display formatted information
    echo "Application Information"
    echo "======================="
    echo "Name:              $display_name"
    echo "App ID:            $app_id"
    echo "Desktop File:      $desktop_file_path"
    
    # Show app file path if available
    if [[ -n "$app_file_path" ]]; then
        echo "App File:          $app_file_path"
    fi
    
    # Show terminal command if available
    if [[ -n "$terminal_command" ]]; then
        echo "Terminal Command:  $terminal_command"
    fi
    
    # Show app class if detected
    if [[ -n "$app_class" ]]; then
        echo "Window Class:      $app_class"
    else
        echo "Window Class:      Not yet detected"
    fi
    
    echo ""
    echo "Launch Methods:"
    echo "  Terminal:        $terminal_status"
    echo "  Desktop:         $desktop_status"
    echo ""
    
    if [[ -n "$last_validated" ]]; then
        echo "Last Validated:    $last_validated"
    else
        echo "Last Validated:    Never"
    fi
    
    debug_function_exit "$function_name"
    return 0
}

registry_list_applications() {
    local filter="${1:-all}"
    local function_name="registry_list_applications"
    local app_list=""
    local line_count=0
    
    debug_function_enter "$function_name" "$@"
    
    case "$filter" in
        all|terminal|desktop)
            debug_log "$function_name" "Filter: $filter"
            ;;
        *)
            echo "Error: Invalid filter: $filter (must be: all, terminal, desktop)"
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid filter: $filter"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # Get filtered application list from database
    app_list=$(db_list_applications "$filter")
    if [[ $? -ne 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to list applications"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if we have any results
    if [[ -z "$app_list" ]]; then
        debug_log "$function_name" "No applications found for filter: $filter"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Format output header
    echo ""
    echo "Available Applications (Filter: $filter)"
    echo ""
    printf "%-30s %-25s %-9s %-8s\n" "NAME" "APP_ID" "TERMINAL" "DESKTOP"
    printf "%-30s %-25s %-9s %-8s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..25})" "$(printf '%.0s-' {1..9})" "$(printf '%.0s-' {1..8})"
    
    # Parse and display results from db_list_applications
    # Format: app_id|display_name|has_terminal_launch|has_desktop_launch
    while IFS='|' read -r app_id display_name has_terminal has_desktop; do
        # Skip empty lines
        [[ -z "$app_id" ]] && continue
        
        # Convert boolean to symbols
        local terminal_status="✗"
        [[ "$has_terminal" == "1" || "$has_terminal" == "TRUE" ]] && terminal_status="✓"
        
        local desktop_status="✗"
        [[ "$has_desktop" == "1" || "$has_desktop" == "TRUE" ]] && desktop_status="✓"
        
        # Truncate display_name if too long
        local display_short="$display_name"
        if [[ ${#display_name} -gt 28 ]]; then
            display_short="${display_name:0:25}..."
        fi
        
        # Truncate app_id if too long
        local app_id_short="$app_id"
        if [[ ${#app_id} -gt 23 ]]; then
            app_id_short="${app_id:0:20}..."
        fi
        
        # Format and display
        printf "%-30s %-25s %-9s %-8s\n" \
            "$display_short" "$app_id_short" "$terminal_status" "$desktop_status"
        
        ((line_count++))
    done <<< "$app_list"
    
    echo ""
    echo "Total: $line_count applications"
    
    debug_function_exit "$function_name"
    return 0
}

registry_get_launch_options() {
    local app_id="$1"
    local function_name="registry_get_launch_options"
    local options=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    
    debug_log "$function_name" "Retrieving launch options for: $app_id"
    
    if ! db_application_exists "$app_id"; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get launch options from database
    options=$(db_get_launch_options "$app_id")
    
    if [[ -z "$options" ]]; then
        echo "No launch options available for: $app_id"
        echo "(This application does not have terminal launch capability)"
        debug_log "$function_name" "No launch options found for $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Display header
    echo "Launch Options for $app_id:"
    echo ""
    
    # Parse and display launch options from database
    # Format: function_name|description
    local index=1
    while IFS='|' read -r func_name description; do
        [[ -z "$func_name" ]] && continue
        printf "  %2d) %-40s - %s\n" "$index" "$func_name" "$description"
        ((index++))
    done <<< "$options"
    
    debug_function_exit "$function_name"
    return 0
}