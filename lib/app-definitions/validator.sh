#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_DEF_VALIDATOR_LOADED" || return 0

json_validate_metadata() {
    local json_file="$1"
    local function_name="json_validate_metadata"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    # Single jq call: validate structure and extract launch options for bash-level checks
    # Output format:
    #   Lines: function_name\tdescription\tparam_count\tparam1_name\tparam1_desc\t...
    local validation_output=""
    if ! validation_output=$(jq -r '
        if (.terminal_command == null) then error("missing required field: terminal_command")
        elif (.launch_options == null) then error("missing required field: launch_options")
        elif (.launch_options | length == 0) then error("launch_options array is empty")
        else
            (.launch_options | to_entries[] |
                .value as $opt | .key as $idx |
                if ($opt.function_name == null or $opt.function_name == "") then
                    error("launch_options[\($idx)] missing function_name")
                elif ($opt.description == null or $opt.description == "") then
                    error("launch_options[\($idx)] missing description")
                else
                    ([$opt.function_name, $opt.description,
                      (($opt.parameters // []) | length | tostring)]
                     + (($opt.parameters // []) | map(.name // "", .description // "") | flatten)
                    ) | @tsv
                end
            )
        end
    ' "$json_file" 2>&1); then
        debug_error "$function_name" "$ERR_INVALID_JSON" "$validation_output"
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ -z "$validation_output" ]]; then
        debug_error "$function_name" "$ERR_INVALID_JSON" "Empty validation output for $json_file"
        debug_function_exit "$function_name"
        return 1
    fi

    # Parse launch options with parameters
    local line=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split into array for field access
        local fields=()
        IFS=$'\t' read -ra fields <<< "$line"

        local func_name="${fields[0]}"
        local param_count="${fields[2]}"

        # Validate function_name format
        if ! [[ "$func_name" =~ ^[a-z_][a-z0-9_]*$ ]]; then
            debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid function_name format: $func_name"
            debug_function_exit "$function_name"
            return 1
        fi

        # Validate parameters (name at index 3+i*2, desc at 4+i*2)
        local p=0
        while [[ $p -lt $param_count ]]; do
            local name_idx=""
            local desc_idx=""
            name_idx=$(( 3 + p * 2 ))
            desc_idx=$(( 4 + p * 2 ))

            local param_name="${fields[$name_idx]:-}"
            local param_desc="${fields[$desc_idx]:-}"

            if [[ -z "$param_name" ]]; then
                debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "$func_name parameter[$p] missing name"
                debug_function_exit "$function_name"
                return 1
            fi

            # Validate PascalCase format
            if ! [[ "$param_name" =~ ^[A-Z][a-zA-Z0-9_]*$ ]]; then
                debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid parameter name format: $param_name (should be PascalCase)"
                debug_function_exit "$function_name"
                return 1
            fi

            if [[ -z "$param_desc" ]]; then
                debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "$func_name parameter[$p] missing description"
                debug_function_exit "$function_name"
                return 1
            fi

            ((p++))
        done
    done <<< "$validation_output"

    debug_log "$function_name" "✓ JSON validation passed for $json_file"
    debug_function_exit "$function_name"
    return 0
}

json_validate_parameters() {
    local json_file="$1"
    local function_name="json_validate_parameters"

    debug_function_enter "$function_name" "$@"

    # Parameter validation is now integrated into json_validate_metadata()
    # This function exists for backward compatibility

    debug_log "$function_name" "✓ Parameter validation passed (handled by json_validate_metadata)"
    debug_function_exit "$function_name"
    return 0
}

json_validate_function_exists() {
    local functions_file="$1"
    local func_name="$2"
    local function_name="json_validate_function_exists"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$functions_file" "functions_file" || return 1
    validate_parameter_pass "$func_name" "func_name" || return 1
    validate_file_exists "$functions_file" || return 1
    
    # Check if function declaration exists in file
    if grep -q "^${func_name}()" "$functions_file"; then
        debug_log "$function_name" "✓ Function $func_name found in $functions_file"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_FUNCTION_NOT_FOUND" "Function $func_name not found in $functions_file"
        debug_function_exit "$function_name"
        return 1
    fi
}