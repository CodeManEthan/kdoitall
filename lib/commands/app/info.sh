#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_INFO_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/display.sh
source "${LIB_DIR}/utils/display.sh"
# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"

app_info() {
    local function_name="app_info"
    local input="$1"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$input" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id or display name"
        echo "Usage: kdoitall app info <app_id|name>" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Try as exact app_id first (suppress error — we handle it below)
    if display_application_info "$input" 2>/dev/null; then
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Not found by app_id — try as display name
    debug_log "$function_name" "app_id lookup failed, trying display name: $input"
    
    local -a matches=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && matches+=("$line")
    done < <(db_find_apps_by_display_name "$input")
    
    if [[ ${#matches[@]} -eq 0 ]]; then
        print_error "Application not found: $input"
        echo "  Try 'kdoitall app list' to see available applications." >&3
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "No match for: $input"
        debug_function_exit "$function_name"
        return 1
    fi
    
    local resolved_app_id=""
    
    if [[ ${#matches[@]} -eq 1 ]]; then
        # Single match — use it directly
        IFS='|' read -r resolved_app_id _ <<< "${matches[0]}"
    else
        # Multiple matches — prompt user to disambiguate
        echo "" >&3
        echo "Multiple applications match '$input':" >&3
        echo "" >&3
        
        local idx=1
        local match_app_id=""
        local match_display_name=""
        for match in "${matches[@]}"; do
            IFS='|' read -r match_app_id match_display_name <<< "$match"
            echo "  [$idx] $match_display_name ($match_app_id)" >&3
            ((idx++))
        done
        
        echo "" >&3
        
        local choice=""
        read -r -p "Select an application (1-${#matches[@]}): " choice
        
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            print_error "Invalid choice."
            debug_function_exit "$function_name"
            return 1
        fi
        
        if [[ "$choice" -lt 1 || "$choice" -gt "${#matches[@]}" ]]; then
            print_error "Invalid choice. Please select 1-${#matches[@]}."
            debug_function_exit "$function_name"
            return 1
        fi
        
        IFS='|' read -r resolved_app_id _ <<< "${matches[$((choice - 1))]}"
    fi
    
    debug_log "$function_name" "Resolved display name '$input' to app_id: $resolved_app_id"
    
    if display_application_info "$resolved_app_id"; then
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "display_application_info failed for resolved id: $resolved_app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}
