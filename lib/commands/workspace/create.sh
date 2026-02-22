#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_CREATE_LOADED" || return 0

# shellcheck source=../../workspace/generator.sh
source "${LIB_DIR}/workspace/generator.sh"
# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../../utils/workspace-validators.sh
source "${LIB_DIR}/utils/workspace-validators.sh"

# State constants for workflow
readonly STATE_SELECT_APP=1
readonly STATE_WINDOW_NAME=2
readonly STATE_LAUNCH_TYPE=3
readonly STATE_DESKTOP=4
readonly STATE_SCREEN=5
readonly STATE_POSITION=6
readonly STATE_LAUNCH_FUNC=7
readonly STATE_PARAMETERS=8
readonly STATE_COMPLETE=9

workspace_create() {
    local workspace_name="$1"
    local description=""
    local display_order=1
    local function_name="workspace_create"
    
    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()
    
    debug_function_enter "$function_name" "$@"
    
    validate_workspace_name "$workspace_name" || return 1
    db_workspace_not_exists "$workspace_name" || return 1

    # 1. Prompt for description
    echo "" >&3
    echo "Creating workspace: $workspace_name" >&3
    echo "Enter workspace description (optional, press Enter to skip):" >&3
    read -r description
    echo "" >&3
    
    # 2. Application addition loop
    while true; do
        echo "=== Add Application to Workspace ===" >&3
        echo "" >&3
        
        if ! add_application_to_workspace "$workspace_name" "$display_order" WORKSPACE_APPS; then
            echo "" >&3
            echo "Application addition cancelled." >&3
            break
        fi
        
        ((display_order++))
        
        echo "" >&3
        echo "Add another application? (y/n)" >&3
        read -r continue_adding
        [[ "$continue_adding" != "y" ]] && break
    done
    
    # Check if any applications were added - must have at least one app
    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_NO_APPLICATIONS" "Workspace creation cancelled"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # 3. Post-launch focus behavior
    local focus_window_name=""
    echo "=== Post-Launch Behavior ===" >&3
    echo "" >&3
    echo "After all windows are launched, would you like to automatically focus one?" >&3
    echo "(This will also switch to that window's virtual desktop)" >&3
    echo "" >&3
    echo "  0) Do nothing (stay on current desktop)" >&3

    local focus_idx=0
    local focus_entry=""
    local focus_app_id=""
    local focus_wname=""
    local focus_display=""
    for focus_entry in "${WORKSPACE_APPS[@]}"; do
        IFS='|' read -r focus_app_id focus_wname _ _ _ _ _ <<< "$focus_entry"

        focus_display=""
        focus_display=$(db_get_display_name "$focus_app_id") || focus_display="$focus_app_id"

        focus_idx=$((focus_idx + 1))
        printf "  %d) %s (%s)\n" "$focus_idx" "$focus_wname" "$focus_display" >&3
    done

    echo "" >&3
    echo "Select (0 to skip):" >&3
    read -r focus_choice

    if [[ "$focus_choice" =~ ^[0-9]+$ ]] && \
       [[ "$focus_choice" -ge 1 ]] && \
       [[ "$focus_choice" -le ${#WORKSPACE_APPS[@]} ]]; then
        local chosen_entry=""
        chosen_entry="${WORKSPACE_APPS[$((focus_choice - 1))]}"
        IFS='|' read -r _ focus_window_name _ _ _ _ _ <<< "$chosen_entry"
    fi

    # Final confirmation before committing to database
    echo "" >&3
    echo "=== Workspace Configuration Summary ===" >&3
    echo "Workspace: $workspace_name" >&3
    echo "Description: ${description:-<none>}" >&3
    echo "" >&3
    echo "Windows (${#WORKSPACE_APPS[@]}):" >&3

    local idx=0
    local app_entry=""
    local summary_app_id=""
    local summary_window_name=""
    local summary_name=""
    local summary_desktop=""
    local summary_screen=""
    local summary_position=""
    for app_entry in "${WORKSPACE_APPS[@]}"; do
        IFS='|' read -r summary_app_id summary_window_name _ summary_desktop summary_screen summary_position _ <<< "$app_entry"

        summary_name=""
        summary_name=$(db_get_display_name "$summary_app_id") || summary_name="$summary_app_id"

        idx=$((idx + 1))
        printf "  %d. %-22s %-30s Screen %s, Desktop %s, %s\n" \
            "$idx" "$summary_name" "($summary_window_name)" "$summary_screen" "$summary_desktop" "$summary_position" >&3
    done

    echo "" >&3
    if [[ -n "$focus_window_name" ]]; then
        local focus_display_name=""
        local focus_entry_lookup=""
        for focus_entry_lookup in "${WORKSPACE_APPS[@]}"; do
            local lookup_app_id=""
            local lookup_wname=""
            IFS='|' read -r lookup_app_id lookup_wname _ _ _ _ _ <<< "$focus_entry_lookup"
            if [[ "$lookup_wname" == "$focus_window_name" ]]; then
                focus_display_name=$(db_get_display_name "$lookup_app_id") || focus_display_name="$lookup_app_id"
                break
            fi
        done
        echo "Focus after launch: $focus_window_name ($focus_display_name)" >&3
    else
        echo "Focus after launch: None" >&3
    fi

    echo "" >&3
    echo "Proceed with workspace creation? (y/n)" >&3
    read -r confirm_create
    
    if [[ "$confirm_create" != "y" ]]; then
        echo "Workspace creation cancelled" >&3
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Create workspace in database
    echo "" >&3
    echo "Creating workspace in database..." >&3
    if ! db_create_workspace "$workspace_name" "$description"; then
        debug_function_exit "$function_name"
        return 1
    fi
    echo "✓ Workspace created in database" >&3
    
    # Set focus window if configured
    if [[ -n "$focus_window_name" ]]; then
        if ! db_set_workspace_focus_window "$workspace_name" "$focus_window_name"; then
            echo "Warning: Failed to set focus window preference" >&3
        fi
    fi
    
    # Generate scripts (passing the configuration array)
    echo "" >&3
    echo "Generating workspace scripts..." >&3
    
    if ! generate_workspace_scripts "$workspace_name" WORKSPACE_APPS; then
        debug_error "$function_name" "$ERR_SCRIPT_GENERATION_FAILED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "✓ Scripts generated successfully" >&3
    echo "" >&3
    echo "================================================================" >&3
    echo "Workspace '$workspace_name' created successfully!" >&3
    echo "================================================================" >&3
    echo "" >&3
    echo "Open with:  kdoitall workspace open $workspace_name" >&3
    echo "Close with: kdoitall workspace close $workspace_name" >&3
    echo "" >&3
    echo "Script file:" >&3
    echo "  ${WORKSPACE_SCRIPTS_DIR}/${workspace_name}.sh" >&3
    echo "" >&3
    
    debug_function_exit "$function_name"
    return 0
}

add_application_to_workspace() {
    local workspace_name="$1"
    local display_order="$2"
    # apps_array_ref="$3"
    local app_id=""
    local window_name=""
    local launch_type=""
    local launch_function=""
    local desktop_number=""
    local screen_number=""
    local position=""
    local parameters=""
    local current_state="$STATE_SELECT_APP"
    local launch_type_interactive=false
    local step_offset=0
    local function_name="add_application_to_workspace"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$3" "apps_array_ref" || return 1
    local -n apps_array_ref="$3"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$display_order" "display_order" || return 1
    
    # State machine loop - navigate through configuration steps
    while [[ "$current_state" != "$STATE_COMPLETE" ]]; do
        case "$current_state" in
            "$STATE_SELECT_APP")
                echo "Step 1: Select Application" >&3
                echo "--------------------------" >&3
                
                if ! app_id=$(select_application_with_retry); then
                    debug_function_exit "$function_name"
                    return 1
                fi
                
                # Get display name and generate window name
                local display_name=""
                display_name=$(db_get_display_name "$app_id")
                
                local instance_count=1
                for app_entry in "${apps_array_ref[@]}"; do
                    local existing_app_id=""
                    existing_app_id=$(echo "$app_entry" | cut -d'|' -f1)
                    
                    if [[ "$existing_app_id" == "$app_id" ]]; then
                        ((instance_count++))
                    fi
                done
                
                local sanitized_display_name=""
                sanitized_display_name=$(echo "$display_name" | \
                    tr '[:upper:]' '[:lower:]' | \
                    tr ' _' '-' | \
                    sed 's/[^a-z0-9-]//g' | \
                    sed 's/--*/-/g')
                
                window_name="${workspace_name}-${sanitized_display_name}-${instance_count}"
                
                current_state="$STATE_WINDOW_NAME"
                ;;
                
            "$STATE_WINDOW_NAME")
                echo "" >&3
                echo "Step 2: Window Name" >&3
                echo "-------------------" >&3
                echo "Window name [$window_name]:" >&3
                read -r custom_name

                if [[ -n "$custom_name" ]]; then
                    window_name="$custom_name"
                fi

                if ! validate_window_name "$window_name"; then
                    echo "" >&3
                    echo "What would you like to do?" >&3
                    echo "1) Try again (re-enter window name)" >&3
                    echo "2) Go back to application selection" >&3
                    echo "3) Cancel" >&3
                    read -r choice

                    case "$choice" in
                        1) continue ;;
                        2)
                            current_state="$STATE_SELECT_APP"
                            continue
                            ;;
                        3)
                            debug_function_exit "$function_name"
                            return 1
                            ;;
                        *)
                            echo "Invalid choice. Please select 1, 2, or 3." >&3
                            continue
                            ;;
                    esac
                fi

                if ! validate_window_name_unique "$window_name" apps_array_ref; then
                    echo "" >&3
                    echo "What would you like to do?" >&3
                    echo "1) Try again (re-enter window name)" >&3
                    echo "2) Go back to application selection" >&3
                    echo "3) Cancel" >&3
                    read -r choice

                    case "$choice" in
                        1) continue ;;
                        2)
                            current_state="$STATE_SELECT_APP"
                            continue
                            ;;
                        3)
                            debug_function_exit "$function_name"
                            return 1
                            ;;
                        *)
                            echo "Invalid choice. Please select 1, 2, or 3." >&3
                            continue
                            ;;
                    esac
                fi

                current_state="$STATE_LAUNCH_TYPE"
                ;;
                
            "$STATE_LAUNCH_TYPE")
                # Check if user input is needed for launch type
                local app_info_lt=""
                app_info_lt=$(db_get_application "$app_id")
                local has_terminal_lt=""
                has_terminal_lt=$(echo "$app_info_lt" | cut -d'|' -f7)
                local has_desktop_lt=""
                has_desktop_lt=$(echo "$app_info_lt" | cut -d'|' -f8)

                if [[ ("$has_terminal_lt" == "1" || "$has_terminal_lt" == "TRUE") && \
                      ("$has_desktop_lt" == "1" || "$has_desktop_lt" == "TRUE") ]]; then
                    launch_type_interactive=true
                    step_offset=0
                    echo "" >&3
                    echo "Step 3: Launch Type" >&3
                    echo "-------------------" >&3
                else
                    launch_type_interactive=false
                    step_offset=-1
                fi

                if ! launch_type=$(choose_launch_type_with_retry "$app_id"); then
                    # User chose to go back or cancel
                    if [[ "$launch_type" == "BACK" ]]; then
                        current_state="$STATE_WINDOW_NAME"
                        continue
                    else
                        debug_function_exit "$function_name"
                        return 1
                    fi
                fi
                
                current_state="$STATE_DESKTOP"
                ;;
                
            "$STATE_DESKTOP")
                echo "" >&3
                echo "Step $((4 + step_offset)): Window Positioning" >&3
                echo "--------------------------" >&3
                
                if ! desktop_number=$(select_desktop_with_retry); then
                    # User chose to go back or cancel
                    if [[ "$desktop_number" == "BACK" ]]; then
                        if [[ "$launch_type_interactive" == true ]]; then
                            current_state="$STATE_LAUNCH_TYPE"
                        else
                            current_state="$STATE_WINDOW_NAME"
                        fi
                        continue
                    elif [[ "$desktop_number" == "CHANGE_APP" ]]; then
                        current_state="$STATE_SELECT_APP"
                        continue
                    else
                        debug_function_exit "$function_name"
                        return 1
                    fi
                fi
                
                current_state="$STATE_SCREEN"
                ;;
                
            "$STATE_SCREEN")
                if ! screen_number=$(select_screen_with_retry); then
                    # User chose to go back or cancel
                    if [[ "$screen_number" == "BACK" ]]; then
                        current_state="$STATE_DESKTOP"
                        continue
                    elif [[ "$screen_number" == "CHANGE_APP" ]]; then
                        current_state="$STATE_SELECT_APP"
                        continue
                    else
                        debug_function_exit "$function_name"
                        return 1
                    fi
                fi
                
                current_state="$STATE_POSITION"
                ;;
                
            "$STATE_POSITION")
                if ! position=$(select_position_with_retry); then
                    # User chose to go back or cancel
                    if [[ "$position" == "BACK" ]]; then
                        current_state="$STATE_SCREEN"
                        continue
                    elif [[ "$position" == "CHANGE_APP" ]]; then
                        current_state="$STATE_SELECT_APP"
                        continue
                    else
                        debug_function_exit "$function_name"
                        return 1
                    fi
                fi
                
                # Determine next state based on launch type
                if [[ "$launch_type" == "$LAUNCH_TYPE_TERMINAL" ]]; then
                    current_state="$STATE_LAUNCH_FUNC"
                else
                    # Desktop launch - set function and skip to complete
                    launch_function="launch_by_app_id"
                    parameters=""
                    current_state="$STATE_COMPLETE"
                fi
                ;;
                
            "$STATE_LAUNCH_FUNC")
                echo "" >&3
                echo "Step $((5 + step_offset)): Launch Function" >&3
                echo "-----------------------" >&3
                
                if ! launch_function=$(select_launch_function_with_retry "$app_id"); then
                    # User chose to go back or cancel
                    if [[ "$launch_function" == "BACK" ]]; then
                        current_state="$STATE_POSITION"
                        continue
                    elif [[ "$launch_function" == "CHANGE_APP" ]]; then
                        current_state="$STATE_SELECT_APP"
                        continue
                    else
                        debug_function_exit "$function_name"
                        return 1
                    fi
                fi
                
                current_state="$STATE_PARAMETERS"
                ;;
                
            "$STATE_PARAMETERS")
                echo "" >&3
                echo "Step $((6 + step_offset)): Function Parameters" >&3
                echo "---------------------------" >&3
                echo "Enter parameters for this function (space-separated):" >&3
                echo "  Example: /path/to/project" >&3
                echo "  (press Enter to skip if no parameters needed)" >&3
                read -r parameters
                
                current_state="$STATE_COMPLETE"
                ;;
        esac
    done
    
    # Store in array for script generation
    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    apps_array_ref+=("$app_id|$window_name|$launch_function|$desktop_number|$screen_number|$position|$parameters")
    
    echo "" >&3
    echo "✓ Added: $window_name ($app_id)" >&3
    
    debug_function_exit "$function_name"
    return 0
}

select_application_with_retry() {
    local function_name="select_application_with_retry"
    
    debug_function_enter "$function_name"
    
    while true; do
        local app_id=""
        app_id=$(select_application)
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            debug_function_exit "$function_name"
            echo "$app_id"
            return 0
        fi
        
        # Selection failed
        echo "" >&3
        echo "What would you like to do?" >&3
        echo "1) Try again" >&3
        echo "2) Cancel" >&3
        read -r choice
        
        case "$choice" in
            1) continue ;;
            2)
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1 or 2." >&3
                ;;
        esac
    done
}

choose_launch_type_with_retry() {
    local app_id="$1"
    local function_name="choose_launch_type_with_retry"
    
    debug_function_enter "$function_name" "$@"
    
    while true; do
        local launch_type=""
        launch_type=$(choose_launch_type "$app_id")
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            debug_function_exit "$function_name"
            echo "$launch_type"
            return 0
        fi
        
        # Selection failed
        echo "" >&3
        echo "What would you like to do?" >&3
        echo "1) Try again" >&3
        echo "2) Go back to application selection" >&3
        echo "3) Cancel" >&3
        read -r choice
        
        case "$choice" in
            1) continue ;;
            2)
                debug_function_exit "$function_name"
                echo "BACK"
                return 1
                ;;
            3)
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1, 2, or 3." >&3
                ;;
        esac
    done
}

select_desktop_with_retry() {
    local function_name="select_desktop_with_retry"
    
    debug_function_enter "$function_name"
    
    while true; do
        echo "Detected virtual desktops: $DETECTED_DESKTOP_COUNT" >&3
        echo "Enter desktop number (1-$DETECTED_DESKTOP_COUNT):" >&3
        read -r desktop_number
        
        # Validate input
        if [[ "$desktop_number" =~ ^[0-9]+$ ]] && \
           [ "$desktop_number" -ge 1 ] && \
           [ "$desktop_number" -le "$DETECTED_DESKTOP_COUNT" ]; then
            debug_log "$function_name" "Selected desktop: $desktop_number"
            debug_function_exit "$function_name"
            echo "$desktop_number"
            return 0
        fi
        
        # Invalid input
        echo "" >&3
        echo "Error: Invalid desktop number (entered: $desktop_number, valid range: 1-$DETECTED_DESKTOP_COUNT)" >&3
        echo "" >&3
        echo "What would you like to do?" >&3
        echo "1) Try again (re-enter desktop number)" >&3
        echo "2) Go back to launch type selection" >&3
        echo "3) Choose different application" >&3
        echo "4) Cancel" >&3
        read -r choice
        
        case "$choice" in
            1) continue ;;
            2)
                debug_function_exit "$function_name"
                echo "BACK"
                return 1
                ;;
            3)
                debug_function_exit "$function_name"
                echo "CHANGE_APP"
                return 1
                ;;
            4)
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1, 2, 3, or 4." >&3
                ;;
        esac
    done
}

select_screen_with_retry() {
    local function_name="select_screen_with_retry"
    
    debug_function_enter "$function_name"
    
    local -A alias_lookup
    local alias_line=""
    local a_target=""
    local a_alias=""
    
    while true; do
        echo "" >&3
        echo "Detected screens:" >&3

        # Prefetch all screen aliases in a single query
        alias_lookup=()
        alias_line=""
        while IFS= read -r alias_line; do
            [[ -z "$alias_line" ]] && continue
            a_target="${alias_line%%|*}"
            a_alias="${alias_line#*|}"
            if [[ -n "${alias_lookup[$a_target]+_}" ]]; then
                alias_lookup[$a_target]="${alias_lookup[$a_target]}, $a_alias"
            else
                alias_lookup[$a_target]="$a_alias"
            fi
        done <<< "$(db_get_all_screen_aliases)"
        
        # Display screens with aliases
        local out=""
        for out in "${SCREEN_OUTPUT_IDS[@]}"; do
            if [[ "${SCREEN_INFO[${out}_ENABLED]}" == "true" ]]; then
                local name="${SCREEN_INFO[${out}_NAME]}"
                
                local alias_display=""
                if [[ -n "${alias_lookup[$name]+_}" ]]; then
                    alias_display=" (aliases: ${alias_lookup[$name]})"
                fi
                
                echo "  $out: ${name}${alias_display}" >&3
            fi
        done
        
        echo "" >&3
        echo "Enter screen (number, name, or alias):" >&3
        read -r screen_input
        
        # Validate input via resolve_screen_reference
        local resolved_screen=""
        if resolved_screen=$(resolve_screen_reference "$screen_input"); then
            debug_log "$function_name" "Selected screen: $resolved_screen (from input: $screen_input)"
            debug_function_exit "$function_name"
            echo "$resolved_screen"
            return 0
        fi
        
        # Invalid input
        echo "" >&3
        echo "Error: Invalid screen reference: $screen_input" >&3
        echo "" >&3
        echo "What would you like to do?" >&3
        echo "1) Try again (re-enter screen)" >&3
        echo "2) Go back to desktop selection" >&3
        echo "3) Choose different application" >&3
        echo "4) Cancel" >&3
        read -r choice
        
        case "$choice" in
            1) continue ;;
            2)
                debug_function_exit "$function_name"
                echo "BACK"
                return 1
                ;;
            3)
                debug_function_exit "$function_name"
                echo "CHANGE_APP"
                return 1
                ;;
            4)
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1, 2, 3, or 4." >&3
                ;;
        esac
    done
}

select_position_with_retry() {
    local function_name="select_position_with_retry"
    local pos_count=""
    pos_count=${#POSITION_MENU_ORDER[@]}

    debug_function_enter "$function_name"

    while true; do
        echo "" >&3
        echo "Available positions:" >&3

        local i=0
        local pos_var=""
        for pos_var in "${POSITION_MENU_ORDER[@]}"; do
            ((i++)) || true
            printf "  %2d) %s\n" "$i" "${!pos_var}" >&3
        done

        read -r pos_choice

        local position=""

        # Validate numeric input in range
        if [[ "$pos_choice" =~ ^[0-9]+$ ]] && (( pos_choice >= 1 && pos_choice <= pos_count )); then
            position="${POSITION_MENU_ORDER[$((pos_choice - 1))]}"
        fi

        if [[ -n "$position" ]]; then
            debug_log "$function_name" "Selected position: $position"
            debug_function_exit "$function_name"
            echo "$position"
            return 0
        fi

        # Invalid input
        echo "" >&3
        echo "Error: Invalid position choice (entered: $pos_choice, valid range: 1-$pos_count)" >&3
        echo "" >&3
        echo "What would you like to do?" >&3
        echo "1) Try again (re-select position)" >&3
        echo "2) Go back to screen selection" >&3
        echo "3) Choose different application" >&3
        echo "4) Cancel" >&3
        read -r choice

        case "$choice" in
            1) continue ;;
            2)
                debug_function_exit "$function_name"
                echo "BACK"
                return 1
                ;;
            3)
                debug_function_exit "$function_name"
                echo "CHANGE_APP"
                return 1
                ;;
            4)
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1, 2, 3, or 4." >&3
                continue
                ;;
        esac
    done
}

select_launch_function_with_retry() {
    local app_id="$1"
    local function_name="select_launch_function_with_retry"
    
    debug_function_enter "$function_name" "$@"
    
    while true; do
        local launch_function=""
        launch_function=$(select_launch_function "$app_id")
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            debug_function_exit "$function_name"
            echo "$launch_function"
            return 0
        fi
        
        # Selection failed
        echo "" >&3
        echo "What would you like to do?" >&3
        echo "1) Try again" >&3
        echo "2) Go back to position selection" >&3
        echo "3) Choose different application" >&3
        echo "4) Cancel" >&3
        read -r choice
        
        case "$choice" in
            1) continue ;;
            2)
                debug_function_exit "$function_name"
                echo "BACK"
                return 1
                ;;
            3)
                debug_function_exit "$function_name"
                echo "CHANGE_APP"
                return 1
                ;;
            4)
                debug_function_exit "$function_name"
                return 1
                ;;
            *)
                echo "Invalid choice. Please select 1, 2, 3, or 4." >&3
                ;;
        esac
    done
}

select_application() {
    local apps=""
    local app_list=()
    local selection=""
    local function_name="select_application"
    
    debug_function_enter "$function_name"
    
    # Get all applications
    apps=$(db_list_applications "all")
    
    if [[ -z "$apps" ]]; then
        echo "Error: No applications found in registry" >&2
        echo "Run 'kdoitall scan' to populate the registry" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Display applications
    echo "" >&3
    echo "Available Applications:" >&3
    echo "======================" >&3
    echo "" >&3
    
    # First pass: detect duplicate display names
    local -A name_counts
    while IFS='|' read -r _ display_name _ _; do
        if [[ -z "${name_counts[$display_name]+_}" ]]; then
            name_counts[$display_name]=1
        else
            ((name_counts[$display_name]++))
        fi
    done <<< "$apps"

    # Second pass: display applications
    local counter=1
    while IFS='|' read -r app_id display_name has_terminal has_desktop; do
        app_list+=("$app_id")
        
        local types=""
        [[ "$has_desktop" == "1" || "$has_desktop" == "TRUE" ]] && types+="[desktop] "
        [[ "$has_terminal" == "1" || "$has_terminal" == "TRUE" ]] && types+="[terminal] "
        types="${types% }"

        local label=""
        if [[ ${name_counts[$display_name]} -gt 1 ]]; then
            label="${display_name} (${app_id})"
        else
            label="$display_name"
        fi
        
        if (( counter % 2 == 0 )); then
            printf "\e[2m%3d) %-45s %s\e[0m\n" "$counter" "$label" "$types" >&3
        else
            printf "%3d) %-45s %s\n" "$counter" "$label" "$types" >&3
        fi
        ((counter++))
    done <<< "$apps"
    
    echo "" >&3
    echo "Legend: [desktop] = Desktop launch, [terminal] = Terminal launch" >&3
    echo "" >&3
    echo "Select application (1-$((counter-1))):" >&3
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [ "$selection" -lt 1 ] || \
       [ "$selection" -ge "$counter" ]; then
        echo "Error: Invalid selection" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    local selected_app_id="${app_list[$((selection-1))]}"
    debug_log "$function_name" "Selected: $selected_app_id"
    debug_function_exit "$function_name"
    echo "$selected_app_id"
}

choose_launch_type() {
    local app_id="$1"
    local app_info=""
    local has_terminal_launch=""
    local has_desktop_launch=""
    local function_name="choose_launch_type"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    app_info=$(db_get_application "$app_id")
    has_terminal_launch=$(echo "$app_info" | cut -d'|' -f7)
    has_desktop_launch=$(echo "$app_info" | cut -d'|' -f8)
    
    # If only one type available, use it
    if [[ ("$has_terminal_launch" == "1" || "$has_terminal_launch" == "TRUE") && ("$has_desktop_launch" == "0" || "$has_desktop_launch" == "FALSE") ]]; then
        debug_log "$function_name" "Only terminal launch available"
        debug_function_exit "$function_name"
        echo "$LAUNCH_TYPE_TERMINAL"
        return 0
    elif [[ ("$has_desktop_launch" == "1" || "$has_desktop_launch" == "TRUE") && ("$has_terminal_launch" == "0" || "$has_terminal_launch" == "FALSE") ]]; then
        debug_log "$function_name" "Only desktop launch available"
        debug_function_exit "$function_name"
        echo "$LAUNCH_TYPE_DESKTOP"
        return 0
    fi
    
    echo "This application supports both launch types:" >&3
    echo "  1) Desktop  - Simple GTK launch (uses .desktop file)" >&3
    echo "  2) Terminal - Advanced launch with custom options" >&3
    read -r type_choice
    
    case "$type_choice" in
        1) 
            debug_log "$function_name" "User selected desktop launch"
            debug_function_exit "$function_name"
            echo "desktop"
            ;;
        2) 
            debug_log "$function_name" "User selected terminal launch"
            debug_function_exit "$function_name"
            echo "terminal"
            ;;
        *) 
            echo "Error: Invalid choice" >&2
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
}

select_launch_function() {
    local app_id="$1"
    local options=""
    local option_list=()
    local function_name="select_launch_function"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    options=$(db_get_launch_options "$app_id")
    
    if [[ -z "$options" ]]; then
        echo "Error: No launch options found for $app_id" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "" >&3
    echo "Available Launch Functions:" >&3
    echo "===========================" >&3
    echo "" >&3
    
    local counter=1
    while IFS='|' read -r function_name description; do
        option_list+=("$function_name")
        printf "%3d) %-40s\n" "$counter" "$function_name" >&3
        printf "     %s\n" "$description" >&3
        echo "" >&3
        ((counter++))
    done <<< "$options"
    
    echo "Select launch function (1-$((counter-1))):" >&3
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [ "$selection" -lt 1 ] || \
       [ "$selection" -ge "$counter" ]; then
        echo "Error: Invalid selection" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    local selected_function="${option_list[$((selection-1))]}"
    debug_log "$function_name" "Selected: $selected_function"
    debug_function_exit "$function_name"
    echo "$selected_function"
}
