#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

safe_kdotool_pattern() {
    local pattern="$1"
    local function_name="safe_kdotool_pattern"

    debug_function_enter "$function_name" "$@"

    # Escape for literal matching in kdotool search regex.
    # A single backslash-prefix strategy handles both JS template-literal
    # safety (backtick, $) and regex literal matching simultaneously.
    # Backslash MUST be escaped first to avoid double-escaping.
    pattern="${pattern//\\/\\\\}"
    pattern="${pattern//\`/\\\`}"
    pattern="${pattern//\$/\\$}"
    pattern="${pattern//./\\.}"
    pattern="${pattern//\*/\\*}"
    pattern="${pattern//+/\\+}"
    pattern="${pattern//\?/\\?}"
    pattern="${pattern//\(/\\(}"
    pattern="${pattern//\)/\\)}"
    pattern="${pattern//\[/\\[}"
    pattern="${pattern//\]/\\]}"
    pattern="${pattern//\{/\\{}"
    pattern="${pattern//\}/\\}}"
    pattern="${pattern//^/\\^}"
    pattern="${pattern//|/\\|}"

    debug_log "$function_name" "$pattern"

    debug_function_exit "$function_name"
    echo "$pattern"
}

safe_json_value() {
    local value="$1"

    # Escape backslash and double-quote for safe embedding in JSON strings.
    # Backslash must be escaped first to avoid double-escaping.
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"

    echo "$value"
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
