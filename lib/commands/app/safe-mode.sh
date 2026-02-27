#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_SAFE_MODE_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../../app/safe-mode.sh
source "${LIB_DIR}/app/safe-mode.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"

app_safe_mode() {
    local subcommand="${1:-}"
    local app_id="${2:-}"
    local function_name="app_safe_mode"
    
    debug_function_enter "$function_name" "$@"

    # Handle skip/reset subcommands
    case "$subcommand" in
        skip)
            if [[ -z "$app_id" ]]; then
                echo "Usage: kdoitall app safe-mode skip <app_id>" >&3
                debug_function_exit "$function_name"
                return 1
            fi
            if ! db_application_exists "$app_id"; then
                echo "Error: Application '$app_id' not found in database." >&3
                debug_function_exit "$function_name"
                return 1
            fi
            db_set_safe_mode_completed "$app_id"
            local display_name
            display_name=$(db_get_display_name "$app_id")
            print_success "Safe mode skipped for $display_name ($app_id)"
            debug_function_exit "$function_name"
            return 0
            ;;
        reset)
            if [[ -z "$app_id" ]]; then
                echo "Usage: kdoitall app safe-mode reset <app_id>" >&3
                debug_function_exit "$function_name"
                return 1
            fi
            if ! db_application_exists "$app_id"; then
                echo "Error: Application '$app_id' not found in database." >&3
                debug_function_exit "$function_name"
                return 1
            fi
            db_clear_safe_mode_data "$app_id"
            local display_name
            display_name=$(db_get_display_name "$app_id")
            print_success "Safe mode data cleared for $display_name ($app_id)"
            echo "  This app will be prompted for safe mode on next workspace open." >&3
            debug_function_exit "$function_name"
            return 0
            ;;
    esac
    
    # --- Interactive menu ---
    
    # Check if there are any apps needing safe mode
    local pending_count
    pending_count=$(db_count_pending_safe_mode_apps)
    
    if [[ "$pending_count" -eq 0 ]]; then
        echo "" >&3
        print_success "No applications need safe mode validation"
        echo "" >&3
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Loop until user quits or no more apps
    while true; do
        # Get fresh count
        pending_count=$(db_count_pending_safe_mode_apps)
        
        if [[ "$pending_count" -eq 0 ]]; then
            echo "" >&3
            print_success "All applications have completed safe mode!"
            echo "" >&3
            debug_function_exit "$function_name"
            return 0
        fi
        
        # Display pending apps
        echo "" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "📋 APPLICATIONS NEEDING SAFE MODE VALIDATION" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3
        
        # Get apps and build array
        local -a app_list=()
        local line_num=1
        
        while IFS='|' read -r app_id display_name; do
            echo "  [$line_num] $display_name" >&3
            echo "      ($app_id)" >&3
            app_list+=("$app_id")
            ((line_num++))
        done < <(db_get_pending_safe_mode_apps)
        
        echo "" >&3
        echo "  [Q] Quit" >&3
        echo "" >&3
        
        # Get user selection
        local choice
        read -r -p "Select an application (1-${#app_list[@]}) or [Q]uit: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
        
        # Handle quit
        if [[ "$choice" == "q" ]]; then
            echo "" >&3
            print_info "Exiting safe mode. $pending_count app(s) still need validation."
            debug_function_exit "$function_name"
            return 0
        fi
        
        # Validate choice is a number
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            print_error "Invalid choice. Please enter a number or 'Q'."
            continue
        fi
        
        # Validate choice is in range
        if [[ "$choice" -lt 1 || "$choice" -gt "${#app_list[@]}" ]]; then
            print_error "Invalid choice. Please select 1-${#app_list[@]}."
            continue
        fi
        
        # Get selected app_id (arrays are 0-indexed)
        local selected_app_id="${app_list[$((choice - 1))]}"
        
        echo "" >&3
        print_info "Starting safe mode for: $selected_app_id"
        echo "" >&3
        
        # Run safe mode for selected app
        if safe_mode_launch_and_detect "$selected_app_id"; then
            echo "" >&3
            print_success "Safe mode completed for $selected_app_id"
            echo "" >&3
            
            # Check if more apps remain
            pending_count=$(db_count_pending_safe_mode_apps)
            
            if [[ "$pending_count" -gt 0 ]]; then
                read -r -p "Continue with another app? [Y/n]: " continue_choice
                continue_choice=$(echo "$continue_choice" | tr '[:upper:]' '[:lower:]')
                
                if [[ "$continue_choice" == "n" ]]; then
                    echo "" >&3
                    print_info "$pending_count app(s) still need validation."
                    print_info "Run 'kdoitall app safe-mode' again when ready."
                    debug_function_exit "$function_name"
                    return 0
                fi
            fi
        else
            echo "" >&3
            print_error "Safe mode failed for $selected_app_id"
            echo "" >&3
            
            read -r -p "Try another app? [Y/n]: " retry_choice
            retry_choice=$(echo "$retry_choice" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$retry_choice" == "n" ]]; then
                debug_function_exit "$function_name"
                return 1
            fi
        fi
    done
}
