#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_and_set_guard "_KDOITALL_APP_SAFE_MODE_COMMAND_LOADED" || return 0

# shellcheck source=../../app/safe-mode.sh
source "${LIB_DIR}/app/safe-mode.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"

app_safe_mode() {
    local function_name="app_safe_mode"
    
    debug_function_enter "$function_name"
    
    # Check if there are any apps needing safe mode
    local pending_count
    pending_count=$(db_count_pending_safe_mode_apps)
    
    if [[ "$pending_count" -eq 0 ]]; then
        echo "" >&3
        echo "✅ No applications need safe mode validation" >&3
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
            echo "✅ All applications have completed safe mode!" >&3
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
            echo "Exiting safe mode. $pending_count app(s) still need validation." >&3
            debug_function_exit "$function_name"
            return 0
        fi
        
        # Validate choice is a number
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            echo "Invalid choice. Please enter a number or 'Q'." >&3
            continue
        fi
        
        # Validate choice is in range
        if [[ "$choice" -lt 1 || "$choice" -gt "${#app_list[@]}" ]]; then
            echo "Invalid choice. Please select 1-${#app_list[@]}." >&3
            continue
        fi
        
        # Get selected app_id (arrays are 0-indexed)
        local selected_app_id="${app_list[$((choice - 1))]}"
        
        echo "" >&3
        echo "Starting safe mode for: $selected_app_id" >&3
        echo "" >&3
        
        # Run safe mode preparation
        if ! prepare_safe_mode_environment; then
            echo "Safe mode cancelled." >&3
            continue
        fi
        
        # Run safe mode for selected app
        if safe_mode_launch_and_detect "$selected_app_id"; then
            echo "" >&3
            echo "✅ Safe mode completed for $selected_app_id" >&3
            echo "" >&3
            
            # Check if more apps remain
            pending_count=$(db_count_pending_safe_mode_apps)
            
            if [[ "$pending_count" -gt 0 ]]; then
                read -r -p "Continue with another app? [Y/n]: " continue_choice
                continue_choice=$(echo "$continue_choice" | tr '[:upper:]' '[:lower:]')
                
                if [[ "$continue_choice" == "n" ]]; then
                    echo "" >&3
                    echo "$pending_count app(s) still need validation." >&3
                    echo "Run 'kdoitall app safe-mode' again when ready." >&3
                    debug_function_exit "$function_name"
                    return 0
                fi
            fi
        else
            echo "" >&3
            echo "❌ Safe mode failed for $selected_app_id" >&3
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
