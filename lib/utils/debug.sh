#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

VERBOSE_MODE=false

# Check command line args
for arg in "$@"; do
    if [[ "$arg" == "--verbose" ]]; then
        VERBOSE_MODE=true
    fi
done

# Color codes
COLOR_RESET="\033[0m"
COLOR_BLUE="\033[34m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_CYAN="\033[36m"
COLOR_MAGENTA="\033[35m"
COLOR_GRAY="\033[90m"

debug_log() {
    local function_name="$1"
    local message="${2:-}"
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} $message" >&2
    fi
}

debug_error() {
    local function_name="$1"
    local error_code="$2"
    local additional_info="${3:-}"
    
    local error_message="${ERROR_MESSAGES[$error_code]}"
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        if [[ -n "$additional_info" ]]; then
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_RED}ERROR: $error_message - $additional_info${COLOR_RESET}" >&2
        else
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_RED}ERROR: $error_message${COLOR_RESET}" >&2
        fi
    else
        if [[ -n "$additional_info" ]]; then
            echo -e "${COLOR_RED}Error:${COLOR_RESET} $error_message - $additional_info" >&2
        else
            echo -e "${COLOR_RED}Error:${COLOR_RESET} $error_message" >&2
        fi
    fi
}

debug_function_enter() {
    local function_name="$1"
    shift
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_GREEN}ENTER${COLOR_RESET}" >&2
        
        if [ $# -gt 0 ]; then
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_YELLOW}PARAMS ($# total)${COLOR_RESET}" >&2
            local i=1
            for param in "$@"; do
                echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET}   ${COLOR_YELLOW}[$i]${COLOR_RESET} = '$param'" >&2
                ((i++))
            done
        fi
    fi
}

debug_function_exit() {
    local function_name="$1"
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_MAGENTA}EXIT${COLOR_RESET}" >&2
        echo "" >&2
    fi
}

debug_array() {
    local array_name="$1"
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        local -n array_ref="$array_name"
        
        echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_BLUE}Array '$array_name' (${#array_ref[@]} elements):${COLOR_RESET}" >&2
        
        if [ "${#array_ref[@]}" -eq 0 ]; then
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_GRAY}(empty)${COLOR_RESET}" >&2
        else
            local i
            for i in "${!array_ref[@]}"; do
                echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_YELLOW}[$i]${COLOR_RESET} = '${array_ref[$i]}'" >&2
            done
        fi
    fi
}

debug_app_windows() {
    local level="${1:-error}"
    
    local should_display=false
    if [[ "$level" == "verbose" ]]; then
        [ "$VERBOSE_MODE" = "true" ] && should_display=true
    else
        [ "$DEBUG_MODE" = "true" ] && should_display=true
    fi
    
    if [ "$should_display" = "true" ]; then
        local count
        count=$(sqlite3 "$KDOITALL_DB" "SELECT COUNT(*) FROM app_windows" 2>/dev/null || echo "0")
        
        echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_BLUE}app_windows table ($count rows):${COLOR_RESET}" >&2
        
        if [ "$count" -eq 0 ]; then
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_GRAY}(empty)${COLOR_RESET}" >&2
        else
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_YELLOW}workspace_name | window_name | uuid | class | is_tab${COLOR_RESET}" >&2
            echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   $(printf '%.0s-' {1..80})" >&2
            
            sqlite3 "$KDOITALL_DB" "SELECT workspace_name, window_name, uuid, class, is_tab FROM app_windows" | while IFS='|' read -r workspace window uuid class is_tab; do
                echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   $workspace | $window | $uuid | $class | $is_tab" >&2
            done
        fi
    fi
}

# Debug function to show chord keys being pressed (verbose only)
debug_chord() {
    if [ "$VERBOSE_MODE" = "true" ]; then
        local keys=("$@")
        local chord_string=""
        
        for key in "${keys[@]}"; do
            if [[ -z "$chord_string" ]]; then
                chord_string="$key"
            else
                chord_string="$chord_string + $key"
            fi
        done
        
        echo -e "${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_MAGENTA}CHORD: $chord_string${COLOR_RESET}" >&2
    fi
}

export VERBOSE_MODE
export -f debug_log
export -f debug_error
export -f debug_function_enter
export -f debug_function_exit
export -f debug_array
export -f debug_app_windows
export -f debug_chord