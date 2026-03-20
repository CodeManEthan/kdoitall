#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_UTILS_DISPLAY_LOADED" || return 0

# Source required database functions
# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"
# shellcheck source=../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=colors.sh
source "${LIB_DIR}/utils/colors.sh"

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

auto_select_title_pattern() {
    local title="$1"
    local display_name="$2"
    local class="$3"
    local function_name="auto_select_title_pattern"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$title" "title" || return 1

    # Parse title into segment suggestions (rightmost first)
    local -a suggestions=()
    mapfile -t suggestions < <(parse_window_title_segments "$title")

    if [[ ${#suggestions[@]} -eq 0 ]]; then
        debug_log "$function_name" "No separators found in title, no pattern to auto-select"
        debug_function_exit "$function_name"
        return 0
    fi

    # Prefer a suggestion containing display_name or class
    local selected_pattern=""
    local display_name_lower=""
    local class_lower=""
    display_name_lower=$(echo "$display_name" | tr '[:upper:]' '[:lower:]')
    class_lower=$(echo "$class" | tr '[:upper:]' '[:lower:]')

    for suggestion in "${suggestions[@]}"; do
        local suggestion_lower=""
        suggestion_lower=$(echo "$suggestion" | tr '[:upper:]' '[:lower:]')

        if [[ -n "$display_name" && "$suggestion_lower" == *"$display_name_lower"* ]]; then
            selected_pattern="$suggestion"
            debug_log "$function_name" "Auto-selected pattern matching display name: '$suggestion'"
            break
        fi

        if [[ -n "$class" && "$suggestion_lower" == *"$class_lower"* ]]; then
            selected_pattern="$suggestion"
            debug_log "$function_name" "Auto-selected pattern matching class: '$suggestion'"
            break
        fi
    done

    # Fallback: use the rightmost suggestion (first in array)
    if [[ -z "$selected_pattern" ]]; then
        selected_pattern="${suggestions[0]}"
        debug_log "$function_name" "No name/class match, using rightmost pattern: '$selected_pattern'"
    fi

    debug_function_exit "$function_name"
    echo "$selected_pattern"
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
    if ! app_info=$(db_get_application "$app_id"); then
        echo "Error: Application not found: $app_id" >&2
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "$app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Parse the pipe-delimited output
    IFS='|' read -r _ app_name display_name desktop_file_path \
        app_directory_path terminal_command app_class \
        has_terminal_launch has_desktop_launch last_validated \
        safe_mode_completed safe_mode_timestamp \
        launch_mode supports_pid_validation executable_path \
        process_name window_title_pattern \
        launch_time_ms has_splash_window splash_duration_ms <<< "$app_info"
    
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
    echo "App Name:            ${app_name:-Not set}" >&3
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

    if [[ -n "$launch_time_ms" ]]; then
        echo "Launch Time:         $launch_time_ms ms" >&3
    fi

    local splash_status="Unknown"
    [[ "$has_splash_window" == "false" ]] && splash_status="No"
    [[ "$has_splash_window" == "true" ]] && splash_status="Yes"
    echo "Splash Window:       $splash_status" >&3
    if [[ "$has_splash_window" == "true" && -n "$splash_duration_ms" ]]; then
        echo "Splash Duration:     ${splash_duration_ms} ms" >&3
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
    if ! app_list=$(db_list_applications "$filter"); then
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
    printf "%-30s %-30s %s\n" "NAME" "APP_ID" "LAUNCH TYPE" >&3
    printf "%-30s %-30s %s\n" "$(printf '%.0s─' {1..28})" "$(printf '%.0s─' {1..28})" "$(printf '%.0s─' {1..20})" >&3
    
    # Parse and display results from db_list_applications
    local line_counter=1
    while IFS='|' read -r app_id display_name has_terminal_launch has_desktop_launch; do
        # Skip empty lines
        [[ -z "$app_id" ]] && continue
        
        local types=""
        [[ "$has_desktop_launch" == "1" || "$has_desktop_launch" == "TRUE" ]] && types+="[desktop] "
        [[ "$has_terminal_launch" == "1" || "$has_terminal_launch" == "TRUE" ]] && types+="[terminal] "
        types="${types% }"
        
        # Truncate display_name if too long
        local display_short="$display_name"
        if [[ ${#display_name} -gt 28 ]]; then
            display_short="${display_name:0:25}..."
        fi
        
        # Truncate app_id if too long
        local app_id_short="$app_id"
        if [[ ${#app_id} -gt 28 ]]; then
            app_id_short="${app_id:0:25}..."
        fi
        
        # Format and display with alternating dim rows
        if (( line_counter % 2 == 0 )); then
            printf "${UI_COLOR_DIM}%-30s %-30s %s${UI_COLOR_RESET}\n" \
                "$display_short" "$app_id_short" "$types" >&3
        else
            printf "%-30s %-30s %s\n" \
                "$display_short" "$app_id_short" "$types" >&3
        fi
        
        ((line_counter++))
        ((line_count++)) || true
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

display_workspace_windows() {
    local workspace_name="$1"
    local function_name="display_workspace_windows"
    local window_details=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    window_details=$(db_get_workspace_window_details "$workspace_name")

    if [[ -z "$window_details" ]]; then
        echo "  No window definitions found." >&3
        debug_function_exit "$function_name"
        return 0
    fi

    # Count windows
    local window_count=0
    window_count=$(echo "$window_details" | wc -l)

    echo "Windows ($window_count):" >&3

    while IFS='|' read -r display_name app_id window_name desktop screen position display_order; do
        local name=""
        name="${display_name:-$app_id}"

        local index=0
        index=$((display_order + 1))

        printf "  %d. %-22s %-30s Screen %s, Desktop %s, %s\n" \
            "$index" "$name" "($window_name)" "$screen" "$desktop" "$position" >&3
    done <<< "$window_details"

    debug_function_exit "$function_name"
    return 0
}

display_workspace_applications() {
    local workspace_name="$1"
    local function_name="display_workspace_applications"
    local window_details=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    window_details=$(db_get_workspace_window_details "$workspace_name")

    if [[ -z "$window_details" ]]; then
        debug_function_exit "$function_name"
        return 0
    fi

    local app_names=""
    while IFS='|' read -r display_name app_id _ _ _ _ _; do
        local name=""
        name="${display_name:-$app_id}"

        if [[ -n "$app_names" ]]; then
            app_names="${app_names}, ${name}"
        else
            app_names="$name"
        fi
    done <<< "$window_details"

    echo "Applications: $app_names" >&3

    debug_function_exit "$function_name"
    return 0
}

display_status_active_workspaces() {
    local function_name="display_status_active_workspaces"
    local result=""

    debug_function_enter "$function_name"

    # Query active workspace windows with live/dead status
    # Returns: workspace_name|window_name|uuid|display_name|window_title|screen|position|is_alive
    result=$(db_get_active_workspace_window_status)

    if [[ -z "$result" ]]; then
        echo "" >&3
        echo "No active workspaces with tracked windows." >&3
        debug_function_exit "$function_name"
        return 0
    fi

    # First pass: determine which workspaces have any dead windows
    local -A workspace_has_dead=()
    while IFS='|' read -r ws_name _ _ _ _ _ _ is_alive; do
        [[ -z "$ws_name" ]] && continue
        if [[ "$is_alive" == "0" ]]; then
            workspace_has_dead["$ws_name"]=1
        fi
    done <<< "$result"

    local current_workspace=""
    local index=0

    while IFS='|' read -r workspace_name window_name uuid display_name window_title defined_screen defined_position is_alive; do
        [[ -z "$workspace_name" ]] && continue

        # Print workspace header when workspace changes
        if [[ "$workspace_name" != "$current_workspace" ]]; then
            current_workspace="$workspace_name"
            index=0

            echo "" >&3
            # Dim workspace header if it has any dead windows
            if [[ -n "${workspace_has_dead[$workspace_name]+_}" ]]; then
                printf "${UI_COLOR_DIM}Workspace: %s${UI_COLOR_RESET}\n" "$current_workspace" >&3
                printf "${UI_COLOR_DIM}───────────────────────────────────────────────────────${UI_COLOR_RESET}\n" >&3
            else
                echo "Workspace: $current_workspace" >&3
                echo "───────────────────────────────────────────────────────" >&3
            fi
        fi

        ((index++)) || true

        if [[ "$is_alive" == "1" ]]; then
            # Live window — get live geometry info
            local live_info=""
            live_info=$(_display_status_live_info "$uuid")

            local desktop=""
            desktop=$(kdotool get_desktop_for_window "$uuid" 2>/dev/null) || true

            # Display window entry (normal)
            printf "  %d. %-22s %s\n" "$index" "$display_name" "$window_name" >&3

            local position_label=""
            if [[ -n "$defined_screen" && -n "$defined_position" ]]; then
                position_label="Desktop ${desktop:-?}, Screen ${defined_screen}, ${defined_position}"
            else
                position_label="N/A"
            fi

            printf "     %-36s %s\n" "$position_label" "$live_info" >&3
        else
            # Dead window — dim styling
            local position_label=""
            if [[ -n "$defined_screen" && -n "$defined_position" ]]; then
                position_label="Desktop ?, Screen ${defined_screen}, ${defined_position}"
            else
                position_label="N/A"
            fi

            printf "${UI_COLOR_DIM}  %d. %-22s %s${UI_COLOR_RESET}\n" "$index" "$display_name" "$window_name" >&3
            printf "${UI_COLOR_DIM}     %-36s %s${UI_COLOR_RESET}\n" "$position_label" "(window not found)" >&3
        fi

    done <<< "$result"

    debug_function_exit "$function_name"
    return 0
}

display_status_untracked_windows() {
    local function_name="display_status_untracked_windows"
    local result=""

    debug_function_enter "$function_name"

    # Query windows not belonging to a real workspace
    result=$(db_get_untracked_windows)

    if [[ -z "$result" ]]; then
        echo "" >&3
        echo "No other tracked windows." >&3
        debug_function_exit "$function_name"
        return 0
    fi

    echo "" >&3
    echo "Other Tracked Windows" >&3
    printf "  %-32s %-22s %s\n" "WINDOW NAME" "CLASS" "TITLE" >&3
    echo "───────────────────────────────────────────────────────" >&3

    while IFS='|' read -r window_name uuid class window_title; do
        [[ -z "$window_name" ]] && continue

        local title_display=""
        title_display="${window_title:-$class}"

        # Truncate class to 18 characters
        if [[ ${#class} -gt 18 ]]; then
            class="${class:0:16}.."
        fi

        printf "  %-32s %-22s %s\n" "$window_name" "$class" "$title_display" >&3
    done <<< "$result"

    debug_function_exit "$function_name"
    return 0
}

_display_status_live_info() {
    local uuid="$1"
    local function_name="_display_status_live_info"
    local geometry=""
    local position=""
    local size=""

    debug_function_enter "$function_name" "$@"

    # Attempt to get geometry from kdotool
    geometry=$(kdotool getwindowgeometry "$uuid" 2>/dev/null) || true

    if [[ -z "$geometry" ]]; then
        debug_log "$function_name" "Window not found: $uuid"
        debug_function_exit "$function_name"
        echo "(window not found)"
        return 0
    fi

    position=$(echo "$geometry" | grep "Position:" | awk '{print $2}')
    size=$(echo "$geometry" | grep "Geometry:" | awk '{print $2}')

    local info=""
    info="${position:-?} ${size:-?}"

    debug_function_exit "$function_name"
    echo "$info"
    return 0
}
