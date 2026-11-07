#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Log levels: 0=silent (errors only), 1=info (key milestones), 2=verbose (everything)
LOG_LEVEL=0
VERBOSE_MODE=false

# Check command line args
for arg in "$@"; do
    case "$arg" in
        --info)
            LOG_LEVEL=1
            ;;
        --verbose)
            LOG_LEVEL=2
            VERBOSE_MODE=true
            ;;
    esac
done

# File logging setup (deferred until config is loaded, call init_file_logging)
KDOITALL_LOG_FILE=""

init_file_logging() {
    if [[ "${LOG_TO_FILE:-disabled}" == "enabled" ]]; then
        mkdir -p "$LOG_DIR"
        KDOITALL_LOG_FILE="${LOG_DIR}/kdoitall-$(date +%Y%m%d-%H%M%S).log"
    fi
}

# Strip ANSI color codes and write to log file
_log_to_file() {
    if [[ -n "$KDOITALL_LOG_FILE" ]]; then
        echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$KDOITALL_LOG_FILE"
    fi
}

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
    local function_name=""
    local message=""
    local line=""
    function_name="$1"
    message="${2:-}"
    line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} $message"
    
    _log_to_file "$line"
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "$line" >&2
    fi
}

info_log() {
    local function_name=""
    local message=""
    local line=""
    function_name="$1"
    message="${2:-}"
    line="${COLOR_GRAY}[INFO  $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_GREEN}$function_name:${COLOR_RESET} $message"
    
    _log_to_file "$line"
    if [ "$LOG_LEVEL" -ge 1 ]; then
        echo -e "$line" >&2
    fi
}

debug_error() {
    local function_name=""
    local error_code=""
    local additional_info=""
    local error_message=""
    local verbose_line=""
    function_name="$1"
    error_code="$2"
    additional_info="${3:-}"
    
    error_message="${ERROR_MESSAGES[$error_code]}"
    
    if [[ -n "$additional_info" ]]; then
        verbose_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_RED}ERROR: $error_message - $additional_info${COLOR_RESET}"
    else
        verbose_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_RED}ERROR: $error_message${COLOR_RESET}"
    fi
    
    _log_to_file "$verbose_line"
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "$verbose_line" >&2
    else
        if [[ -n "$additional_info" ]]; then
            echo -e "${COLOR_RED}Error:${COLOR_RESET} $error_message - $additional_info" >&2
        else
            echo -e "${COLOR_RED}Error:${COLOR_RESET} $error_message" >&2
        fi
    fi
}

debug_function_enter() {
    local function_name=""
    function_name="$1"
    shift
    
    local enter_line=""
    enter_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_GREEN}ENTER${COLOR_RESET}"
    _log_to_file "$enter_line"
    
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "$enter_line" >&2
    fi

    if [ $# -gt 0 ]; then
        local params_line=""
        params_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_YELLOW}PARAMS ($# total)${COLOR_RESET}"
        _log_to_file "$params_line"
        if [ "$VERBOSE_MODE" = "true" ]; then
            echo -e "$params_line" >&2
        fi
        
        local i=""
        i=1
        for param in "$@"; do
            local param_line=""
            param_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET}   ${COLOR_YELLOW}[$i]${COLOR_RESET} = '$param'"
            _log_to_file "$param_line"
            if [ "$VERBOSE_MODE" = "true" ]; then
                echo -e "$param_line" >&2
            fi
            ((i++))
        done
    fi
}

debug_function_exit() {
    local function_name=""
    local line=""
    function_name="$1"
    line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_CYAN}$function_name:${COLOR_RESET} ${COLOR_MAGENTA}EXIT${COLOR_RESET}"
    
    _log_to_file "$line"
    _log_to_file ""
    if [ "$VERBOSE_MODE" = "true" ]; then
        echo -e "$line" >&2
        echo "" >&2
    fi
}

debug_array() {
    local array_name=""
    array_name="$1"
    local -n array_ref="$array_name"
    
    local header=""
    header="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_BLUE}Array '$array_name' (${#array_ref[@]} elements):${COLOR_RESET}"
    _log_to_file "$header"
    
    if [ "${#array_ref[@]}" -eq 0 ]; then
        local empty_line=""
        empty_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_GRAY}(empty)${COLOR_RESET}"
        _log_to_file "$empty_line"
        if [ "$VERBOSE_MODE" = "true" ]; then
            echo -e "$header" >&2
            echo -e "$empty_line" >&2
        fi
    else
        if [ "$VERBOSE_MODE" = "true" ]; then
            echo -e "$header" >&2
        fi
        local i
        for i in "${!array_ref[@]}"; do
            local elem_line=""
            elem_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_YELLOW}[$i]${COLOR_RESET} = '${array_ref[$i]}'"
            _log_to_file "$elem_line"
            if [ "$VERBOSE_MODE" = "true" ]; then
                echo -e "$elem_line" >&2
            fi
        done
    fi
}

debug_app_windows() {
    local level=""
    level="${1:-verbose}"
    
    local should_display=""
    should_display=false
    if [[ "$level" == "info" ]]; then
        [ "$LOG_LEVEL" -ge 1 ] && should_display=true
    else
        [ "$LOG_LEVEL" -ge 2 ] && should_display=true
    fi
    
    # Skip entirely if neither displaying nor logging to file
    if [[ "$should_display" != "true" && -z "$KDOITALL_LOG_FILE" ]]; then
        return 0
    fi
    
    local count=""
    count=$(db_count_tracked_windows)
    
    local header=""
    header="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET} ${COLOR_BLUE}app_windows table ($count rows):${COLOR_RESET}"
    _log_to_file "$header"
    [ "$should_display" = "true" ] && echo -e "$header" >&2
    
    if [ "$count" -eq 0 ]; then
        local empty_line=""
        empty_line="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_GRAY}(empty)${COLOR_RESET}"
        _log_to_file "$empty_line"
        [ "$should_display" = "true" ] && echo -e "$empty_line" >&2
    else
        local col_header=""
        local separator=""
        col_header="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   ${COLOR_YELLOW}workspace_name | window_name | uuid | class | is_tab${COLOR_RESET}"
        separator="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   $(printf '%.0s-' {1..80})"
        _log_to_file "$col_header"
        _log_to_file "$separator"
        [ "$should_display" = "true" ] && echo -e "$col_header" >&2
        [ "$should_display" = "true" ] && echo -e "$separator" >&2
        
        db_dump_tracked_windows | while IFS='|' read -r workspace window uuid class is_tab; do
            local row=""
            row="${COLOR_GRAY}[DEBUG $(date +%H:%M:%S.%3N)]${COLOR_RESET}   $workspace | $window | $uuid | $class | $is_tab"
            _log_to_file "$row"
            [ "$should_display" = "true" ] && echo -e "$row" >&2
        done
    fi
}

export LOG_LEVEL
export VERBOSE_MODE
export KDOITALL_LOG_FILE
export -f _log_to_file
export -f init_file_logging
export -f info_log
export -f debug_log
export -f debug_error
export -f debug_function_enter
export -f debug_function_exit
export -f debug_array
export -f debug_app_windows