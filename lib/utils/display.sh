#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_and_set_guard "_KDOITALL_UTILS_DISPLAY_LOADED" || return 0

# Source required database functions
# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"
# shellcheck source=../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"

display_tracked_windows() {
    local function_name="display_tracked_windows"
    
    debug_function_enter "$function_name"
    
    # Validate that arrays are populated
    validate_global_array_populated DB_UUIDS "DB_UUIDS" || return 1
    
    if [[ ${#DB_UUIDS[@]} -eq 0 ]]; then
        echo "No windows currently tracked in database."
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Display header
    printf "%-19s %-30s %s\n" "UUID" "Class" "Window Title"
    echo "─────────────────── ────────────────────────────── ─────────────────────────────────"
    
    # Display each window
    local i
    for i in "${!DB_UUIDS[@]}"; do
        printf "%-19s %-30s %s\n" \
            "${DB_UUIDS[$i]}" \
            "${DB_CLASSES[$i]}" \
            "${DB_TITLES[$i]}"
    done
    
    debug_function_exit "$function_name"
    return 0
}

# This function splits window titles on " - " and " — " separators and
# generates suggestions for unique window title patterns.
parse_window_title_segments() {
    local title="$1"
    local function_name="parse_window_title_segments"
    local -a suggestions=()
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$title" "title" || return 1
    
    local remaining="$title"
    local -a separator_positions=()  # Will store: "position|separator_text"
    local position=0
    
    # Find all separators (both types) and their positions
    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" =~ ^(.*?)(\ —\ )(.*) ]]; then
            local before="${BASH_REMATCH[1]}"
            local sep="${BASH_REMATCH[2]}"
            position=$((position + ${#before}))
            separator_positions+=("$position|$sep")
            position=$((position + ${#sep}))
            remaining="${BASH_REMATCH[3]}"
        elif [[ "$remaining" =~ ^(.*?)(\ -\ )(.*) ]]; then
            local before="${BASH_REMATCH[1]}"
            local sep="${BASH_REMATCH[2]}"
            position=$((position + ${#before}))
            separator_positions+=("$position|$sep")
            position=$((position + ${#sep}))
            remaining="${BASH_REMATCH[3]}"
        else
            break
        fi
    done
    
    if [[ ${#separator_positions[@]} -eq 0 ]]; then
        debug_log "$function_name" "No separators found in title"
        debug_function_exit "$function_name"
        return 0
    fi
    
    local sep_count=${#separator_positions[@]}
    
    # Build suffix suggestions (rightmost first)
    for ((i = sep_count - 1; i >= 0; i--)); do
        local sep_info="${separator_positions[$i]}"
        local sep_pos="${sep_info%%|*}"
        local sep_text="${sep_info#*|}"
        
        # Extract from this separator to the end
        local suffix="${title:$sep_pos}"
        suggestions+=("$suffix")
    done
    
    # Build prefix suggestions (leftmost first, but we'll add them after suffixes)
    for ((i = 0; i < sep_count; i++)); do
        local sep_info="${separator_positions[$i]}"
        local sep_pos="${sep_info%%|*}"
        local sep_text="${sep_info#*|}"
        
        # Extract from start to after this separator
        local end_pos=$((sep_pos + ${#sep_text}))
        local prefix="${title:0:$end_pos}"
        
        # Only add if it's not already in suggestions (avoid duplicates)
        local already_exists=false
        for existing in "${suggestions[@]}"; do
            if [[ "$existing" == "$prefix" ]]; then
                already_exists=true
                break
            fi
        done
        
        if [[ "$already_exists" == "false" ]]; then
            suggestions+=("$prefix")
        fi
    done
    
    debug_log "$function_name" "Generated ${#suggestions[@]} suggestions"
    debug_function_exit "$function_name"
    
    # Return suggestions as newline-separated list
    printf '%s\n' "${suggestions[@]}"
    return 0
}

display_application_info() {
    local app_id="$1"
    local function_name="registry_get_application_info"
    local app_info=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    debug_log "$function_name" "Retrieving info for: $app_id"
    
    # Get application details from database
    app_info=$(db_get_application "$app_id")
    if [[ $? -ne 0 ]]; then
        echo "Error: Application not found: $app_id" >&2
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Parse the pipe-delimited output
    IFS='|' read -r _ display_name desktop_file_path \
        app_directory_path terminal_command app_class \
        has_terminal_launch has_desktop_launch last_validated \
        safe_mode_completed safe_mode_timestamp \
        launch_mode supports_pid_validation executable_path \
        process_name window_title_pattern \
        launch_time_ms <<< "$app_info"
    
    # Convert boolean values for display
    local terminal_status="Not Available"
    [[ "$has_terminal_launch" == "1" || "$has_terminal_launch" == "TRUE" ]] && terminal_status="Available"
    
    local desktop_status="Not Available"
    [[ "$has_desktop_launch" == "1" || "$has_desktop_launch" == "TRUE" ]] && desktop_status="Available"
    
    local safe_mode_status="Not Completed"
    [[ "$safe_mode_completed" == "1" || "$safe_mode_completed" == "TRUE" ]] && safe_mode_status="Completed"
    
    local pid_validation_status="Not Supported"
    [[ "$supports_pid_validation" == "1" || "$supports_pid_validation" == "TRUE" ]] && pid_validation_status="Supported"
    

    # Display formatted information
    echo "Application Information" >&3
    echo "=========================================================" >&3
    echo "Name:                $display_name" >&3
    echo "App ID:              $app_id" >&3
    echo "Desktop File:        $desktop_file_path" >&3
    
    # Show app file path if available
    if [[ -n "$app_directory_path" ]]; then
        echo "App Directory:       $app_directory_path" >&3
    fi
    
    # Show terminal command if available
    if [[ -n "$terminal_command" ]]; then
        echo "Terminal Command:    $terminal_command" >&3
    fi
    
    # Show app class if detected
    if [[ -n "$app_class" ]]; then
        echo "Window Class:        $app_class" >&3
    else
        echo "Window Class:        Not yet detected" >&3
    fi

    # Show window title pattern if detected
    if [[ -n "$window_title_pattern" ]]; then
        echo "Title Pattern:       $window_title_pattern" >&3
    else
        echo "Title Pattern:       Not yet detected" >&3
    fi
    
    echo "" >&3
    echo "Launch Methods:" >&3
    echo "  Terminal:          $terminal_status" >&3
    echo "  Desktop:           $desktop_status" >&3
    echo "" >&3
    
    if [[ -n "$last_validated" ]]; then
        echo "Last Validated:      $last_validated" >&3
    else
        echo "Last Validated:      Never" >&3
    fi

    if [[ -n "$safe_mode_completed" ]]; then
        echo "Safe Mode:           $safe_mode_status $safe_mode_timestamp" >&3
    fi

    if [[ -n "$launch_mode" ]]; then
        echo "Launch Mode:         $launch_mode" >&3
    else
        echo "Launch Mode:         Unknown" >&3
    fi
    
    if [[ -n "$supports_pid_validation" ]]; then
        echo "PID Validation:      $pid_validation_status" >&3
        if [[ -n "$executable_path" ]]; then
            echo "Executable Path:     $executable_path" >&3
        else
            echo "Executable Path:     Not Found" >&3
        fi
        if [[ -n "$process_name" ]]; then
            echo "Process Name:        $process_name" >&3
        else
            echo "Process Name:        Not Found" >&3
        fi
    else
        echo "PID Validation:      Not Completed" >&3
    fi

    if [[ -n "$window_title_pattern" ]]; then
        echo "Window Title:        $window_title_pattern" >&3
    fi

    if [[ -n "$launch_time_ms" ]]; then
        echo "Launch Time:         $launch_time_ms ms" >&3
    fi

    debug_function_exit "$function_name"
    return 0
}

display_applications_list() {
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
            echo "Error: Invalid filter: $filter (must be: all, terminal, desktop)" >&2
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
    echo "" >&3
    echo "Available Applications (Filter: $filter)" >&3
    echo "" >&3
    printf "%-30s %-25s %-9s %-8s\n" "NAME" "APP_ID" "TERMINAL" "DESKTOP" >&3
    printf "%-30s %-25s %-9s %-8s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..25})" "$(printf '%.0s-' {1..9})" "$(printf '%.0s-' {1..8})" >&3
    
    # Parse and display results from db_list_applications
    while IFS='|' read -r app_id display_name has_terminal_launch has_desktop_launch; do
        # Skip empty lines
        [[ -z "$app_id" ]] && continue
        
        # Convert boolean to symbols
        local terminal_status="✗"
        [[ "$has_terminal_launch" == "1" || "$has_terminal_launch" == "TRUE" ]] && terminal_status="✓"
        
        local desktop_status="✗"
        [[ "$has_desktop_launch" == "1" || "$has_desktop_launch" == "TRUE" ]] && desktop_status="✓"
        
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
            "$display_short" "$app_id_short" "$terminal_status" "$desktop_status" >&3
        
        ((line_count++))
    done <<< "$app_list"
    
    echo "" >&3
    echo "Total: $line_count applications" >&3
    
    debug_function_exit "$function_name"
    return 0
}

display_launch_options() {
    local app_id="$1"
    local function_name="registry_get_launch_options"
    local options=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    debug_log "$function_name" "Retrieving launch options for: $app_id"
    
    if ! db_application_exists "$app_id"; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get launch options from database
    options=$(db_get_launch_options "$app_id")
    
    if [[ -z "$options" ]]; then
        echo "No launch options available for: $app_id" >&3
        echo "(This application does not have terminal launch capability)" >&3
        debug_log "$function_name" "No launch options found for $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Display header
    echo "Launch Options for $app_id:" >&3
    echo "" >&3
    
    # Parse and display launch options from database
    # Format: function_name|description
    local index=1
    while IFS='|' read -r func_name description; do
        [[ -z "$func_name" ]] && continue
        printf "  %2d) %-40s - %s\n" "$index" "$func_name" "$description" >&3
        ((index++))
    done <<< "$options"
    
    debug_function_exit "$function_name"
    return 0
}

display_launch_parameters() {
    local app_id="$1"
    local function_id="$2"
    local function_name="registry_get_launch_parameters"
    local parameters=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$function_id" "function_id" || return 1
    
    debug_log "$function_name" "Retrieving launch parameters for: $app_id (function_id: $function_id)"
    
    if ! db_application_exists "$app_id"; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get launch parameters from database
    parameters=$(db_get_launch_parameters "$app_id" "$function_id")
    
    if [[ -z "$parameters" ]]; then
        debug_log "$function_name" "No launch parameters found for $app_id (function_id: $function_id)"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Display header
    echo "Launch Parameters for function_id $function_id:" >&3
    echo "" >&3
    
    # Parse and display launch parameters from database
    # Format: function_name|description
    local index=1
    while IFS='|' read -r param_name description; do
        [[ -z "$param_name" ]] && continue
        printf "  %2d) %-40s - %s\n" "$index" "$param_name" "$description" >&3
        ((index++))
    done <<< "$parameters"
    
    debug_function_exit "$function_name"
    return 0
}