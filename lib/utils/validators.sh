#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

safe_name() {
    local name="$1"
    local function_name="safe_name"

    debug_function_enter "$function_name" "$@"

    # Escape special characters
    name="${name//\(/\\(}"
    name="${name//\)/\\)}"
    name="${name//\[/\\[}"
    name="${name//\]/\\]}"

    # Pass Name
    debug_log "$function_name" "$name"

    debug_function_exit "$function_name"
    echo "$name" 
}

safe_file() {
    local file_path="$1"
    local safe_file_path=""
    local function_name="safe_file"

    debug_function_enter "$function_name" "$@"
    
    # Apply 'safe_name' to file_path (if file exists and is not empty)
    if [[ -f "$file_path" ]]; then
        if [[ -s "$file_path" ]]; then
            safe_file_path=$(safe_name "$file_path")

            # Pass Safe File Path (only log if path actually changed)
            if [[ "$file_path" != "$safe_file_path" ]]; then
                debug_log "$function_name" "Renamed $file_path to $safe_file_path"
            fi

            debug_function_exit "$function_name"
            echo "$safe_file_path"
            return 0
        else
            debug_error "$function_name" "$ERR_FILE_IS_EMPTY" "$file_path"
            debug_function_exit "$function_name"
            return 1
        fi
    else
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$file_path"
        debug_function_exit "$function_name"
        return 1
    fi
}

safe_directory() {
    local directory_path="$1"
    local safe_directory_path=""
    local function_name="safe_directory"

    debug_function_enter "$function_name" "$@"
    
    # Apply 'safe_name' to directory_path (if directory exists)
    if [[ -d "$directory_path" ]]; then
        safe_directory_path=$(safe_name "$directory_path")

        # Pass Safe Directory Path (only log if path actually changed)
        if [[ "$directory_path" != "$safe_directory_path" ]]; then
            debug_log "$function_name" "Renamed $directory_path to $safe_directory_path"
        fi

        debug_function_exit "$function_name"
        echo "$safe_directory_path"
        return 0
    fi
    
    debug_error "$function_name" "$ERR_DIRECTORY_NOT_FOUND" "$directory_path"
    debug_function_exit "$function_name"
    return 1
}

validate_app_id_format() {
    local app_id="$1"
    local function_name="validate_app_id_format"

    if ! [[ "$app_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid app_id format: $app_id"
        return 1
    fi
}

validate_parameter_pass() {
    local parameter="$1"
    local parameter_name="$2"
    
    if [[ -z "$parameter" ]]; then
        local function_name="validate_parameter_pass"

        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "$parameter_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

validate_global_array_populated() {
    local -n array_ref="$1"
    local array_name="$2"
    local function_name="validate_global_array_populated"
    
    if [[ ${#array_ref[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_INVALID_STATE" "$array_name is empty"
        return 1
    fi
    
    return 0
}

validate_file_exists() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        local function_name="validate_file_exists"

        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$path"
        debug_function_exit "$function_name"
        return 1
    fi
}

validate_directory_exists() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        local function_name="validate_directory_exists"

        debug_error "$function_name" "$ERR_DIRECTORY_NOT_FOUND" "$path"
        debug_function_exit "$function_name"
        return 1
    fi
}

validate_command_exists() {
    local terminal_command="$1"
    local function_name="registry_validate_terminal_command"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$terminal_command" "terminal_command" || return 1
    
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
