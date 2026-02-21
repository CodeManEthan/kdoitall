#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_JSON_PARSER_LOADED" || return 0

json_get_launch_options() {
    local json_file="$1"
    local function_name="json_get_launch_options"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local launch_options=""
    launch_options=$(jq -c '.launch_options' "$json_file")
    
    if [[ -z "$launch_options" ]] || [[ "$launch_options" == "null" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "launch_options not found in $json_file"
        return 1
    fi
    
    echo "$launch_options"
    debug_function_exit "$function_name"
    return 0
}

json_get_launch_option_parameters() {
    local json_file="$1"
    local option_index="$2"
    local function_name="json_get_launch_option_parameters"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_parameter_pass "$option_index" "option_index" || return 1
    validate_file_exists "$json_file" || return 1
    
    local parameters=""
    parameters=$(jq -c ".launch_options[$option_index].parameters // []" "$json_file")
    
    echo "$parameters"
    debug_function_exit "$function_name"
    return 0
}

json_get_app_id() {
    local json_file="$1"
    local function_name="json_get_app_id"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local app_id=""
    app_id=$(jq -r '.app_id // empty' "$json_file")
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "app_id not found in $json_file"
        return 1
    fi
    
    echo "$app_id"
    debug_function_exit "$function_name"
    return 0
}

json_get_app_class() {
    local json_file="$1"
    local function_name="json_get_app_class"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local app_class=""
    app_class=$(jq -r '.app_class // empty' "$json_file")
    
    echo "$app_class"
    debug_function_exit "$function_name"
    return 0
}

json_get_window_title_pattern() {
    local json_file="$1"
    local function_name="json_get_window_title_pattern"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local window_title_pattern=""
    window_title_pattern=$(jq -r '.window_title_pattern // empty' "$json_file")
    
    echo "$window_title_pattern"
    debug_function_exit "$function_name"
    return 0
}

json_get_launch_mode() {
    local json_file="$1"
    local function_name="json_get_launch_mode"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local launch_mode=""
    launch_mode=$(jq -r '.launch_mode // empty' "$json_file")
    
    echo "$launch_mode"
    debug_function_exit "$function_name"
    return 0
}

json_get_launch_type() {
    local json_file="$1"
    local function_name="json_get_launch_type"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local launch_type=""
    launch_type=$(jq -r '.launch_type // empty' "$json_file")
    
    echo "$launch_type"
    debug_function_exit "$function_name"
    return 0
}

json_get_terminal_command() {
    local json_file="$1"
    local function_name="json_get_terminal_command"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local terminal_command=""
    terminal_command=$(jq -r '.terminal_command // empty' "$json_file")
    
    if [[ -z "$terminal_command" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "terminal_command not found in $json_file"
        return 1
    fi
    
    echo "$terminal_command"
    debug_function_exit "$function_name"
    return 0
}

json_get_launch_options_count() {
    local json_file="$1"
    local function_name="json_get_launch_options_count"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    local count=""
    count=$(jq -r '.launch_options | length' "$json_file")
    
    echo "$count"
    debug_function_exit "$function_name"
    return 0
}

json_get_launch_option_function_name() {
    local json_file="$1"
    local option_index="$2"
    local function_name="json_get_launch_option_function_name"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_parameter_pass "$option_index" "option_index" || return 1
    validate_file_exists "$json_file" || return 1
    
    local func_name=""
    func_name=$(jq -r ".launch_options[$option_index].function_name // empty" "$json_file")
    
    if [[ -z "$func_name" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "function_name not found at index $option_index"
        return 1
    fi
    
    echo "$func_name"
    debug_function_exit "$function_name"
    return 0
}

json_get_launch_option_description() {
    local json_file="$1"
    local option_index="$2"
    local function_name="json_get_launch_option_description"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_parameter_pass "$option_index" "option_index" || return 1
    validate_file_exists "$json_file" || return 1
    
    local description=""
    description=$(jq -r ".launch_options[$option_index].description // empty" "$json_file")
    
    if [[ -z "$description" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "description not found at index $option_index"
        return 1
    fi
    
    echo "$description"
    debug_function_exit "$function_name"
    return 0
}

json_get_function_parameters() {
    local json_file="$1"
    local func_name="$2"
    local function_name="json_get_function_parameters"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_parameter_pass "$func_name" "func_name" || return 1
    validate_file_exists "$json_file" || return 1
    
    local parameters=""
    parameters=$(jq -c ".launch_options[] | select(.function_name == \"$func_name\") | .parameters // []" "$json_file" | head -n 1)
    
    if [[ -z "$parameters" ]]; then
        echo "[]"
    else
        echo "$parameters"
    fi
    
    debug_function_exit "$function_name"
    return 0
}

json_pretty_print() {
    local json_file="$1"
    local function_name="json_pretty_print"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    jq '.' "$json_file"
    return $?
}

json_get_all_metadata() {
    local json_file="$1"
    local function_name="json_get_all_metadata"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1

    # Single jq call to extract all top-level metadata as TSV
    local result=""
    result=$(jq -r '[
        (.terminal_command // ""),
        (.app_class // ""),
        (.launch_mode // ""),
        (.window_title_pattern // "")
    ] | @tsv' "$json_file")

    if [[ -z "$result" ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "Failed to extract metadata from $json_file"
        debug_function_exit "$function_name"
        return 1
    fi

    echo "$result"
    debug_function_exit "$function_name"
    return 0
}

json_get_all_launch_options() {
    local json_file="$1"
    local function_name="json_get_all_launch_options"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1

    # Single jq call: one line per launch option
    # Format: function_name\tdescription\tparams_json
    jq -r '.launch_options[] |
        [.function_name, .description, (.parameters // [] | @json)] |
        @tsv
    ' "$json_file"

    debug_function_exit "$function_name"
    return 0
}