#!/bin/bash

check_and_set_guard "_KDOITALL_APP_DEF_VALIDATOR_LOADED" || return 0


json_validate_metadata() {
    local json_file="$1"
    local function_name="json_validate_metadata"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameters
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    # Basic JSON syntax validation
    if ! jq empty "$json_file" 2>/dev/null; then
        debug_error "$function_name" "$ERR_INVALID_JSON" "Invalid JSON syntax in $json_file"
        return 1
    fi
    
    # Validate required fields exist
    local required_fields=("app_id" "terminal_command" "launch_options")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$json_file" &>/dev/null; then
            debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "Missing required field: $field"
            return 1
        fi
    done
    
    # Validate app_id format (lowercase letters, numbers, dots, hyphens, underscores)
    local app_id=""
    app_id=$(jq -r '.app_id' "$json_file")
    if ! [[ "$app_id" =~ ^[a-z0-9._-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid app_id format: $app_id"
        return 1
    fi
    
    # Validate launch_mode enum
    local launch_mode=""
    launch_mode=$(jq -r '.launch_mode // empty' "$json_file")
    if [[ -n "$launch_mode" ]] && [[ "$launch_mode" != "LAUNCH_MODE_SINGLE" ]] && [[ "$launch_mode" != "LAUNCH_MODE_UNIQUE" ]] && [[ "$launch_mode" != "LAUNCH_MODE_MULTI" ]]; then
        debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid launch_mode: $launch_mode"
        return 1
    fi
    
    # Validate launch_type enum
    local launch_type=""
    launch_type=$(jq -r '.launch_type // empty' "$json_file")
    if [[ -n "$launch_type" ]] && [[ "$launch_type" != "LAUNCH_TYPE_TERMINAL" ]] && [[ "$launch_type" != "LAUNCH_TYPE_DESKTOP" ]]; then
        debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid launch_type: $launch_type"
        return 1
    fi
    
    # Validate launch_options is a non-empty array
    local launch_options_count=""
    launch_options_count=$(jq -r '.launch_options | length' "$json_file")
    if [[ "$launch_options_count" -eq 0 ]]; then
        debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "launch_options array is empty"
        return 1
    fi
    
    # Validate each launch option has required fields
    local i=0
    while [[ $i -lt $launch_options_count ]]; do
        local func_name=""
        func_name=$(jq -r ".launch_options[$i].function_name // empty" "$json_file")
        if [[ -z "$func_name" ]]; then
            debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "launch_options[$i] missing function_name"
            return 1
        fi
        
        # Validate function_name format (lowercase letters, numbers, underscores)
        if ! [[ "$func_name" =~ ^[a-z_][a-z0-9_]*$ ]]; then
            debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid function_name format: $func_name"
            return 1
        fi
        
        local description=""
        description=$(jq -r ".launch_options[$i].description // empty" "$json_file")
        if [[ -z "$description" ]]; then
            debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "launch_options[$i] missing description"
            return 1
        fi
        
        ((i++))
    done
    
    debug_log "$function_name" "✓ JSON validation passed for $json_file"
    debug_function_exit "$function_name"
    return 0
}

json_validate_parameters() {
    local json_file="$1"
    local function_name="json_validate_parameters"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$json_file" "json_file" || return 1
    validate_file_exists "$json_file" || return 1
    
    # Check each launch option's parameters
    local launch_options_count=""
    launch_options_count=$(jq -r '.launch_options | length' "$json_file")
    
    local i=0
    while [[ $i -lt $launch_options_count ]]; do
        local params_exist=""
        params_exist=$(jq -e ".launch_options[$i].parameters" "$json_file" &>/dev/null && echo "yes" || echo "no")
        
        if [[ "$params_exist" == "yes" ]]; then
            local param_count=""
            param_count=$(jq -r ".launch_options[$i].parameters | length" "$json_file")
            
            local j=0
            while [[ $j -lt $param_count ]]; do
                # Validate parameter has name and description
                local param_name
                param_name=$(jq -r ".launch_options[$i].parameters[$j].name // empty" "$json_file")
                if [[ -z "$param_name" ]]; then
                    debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "launch_options[$i].parameters[$j] missing name"
                    return 1
                fi
                
                # Validate parameter name format (PascalCase: starts with uppercase)
                if ! [[ "$param_name" =~ ^[A-Z][a-zA-Z0-9_]*$ ]]; then
                    debug_error "$function_name" "$ERR_INVALID_VALUE" "Invalid parameter name format: $param_name (should be PascalCase)"
                    return 1
                fi
                
                local param_desc=""
                param_desc=$(jq -r ".launch_options[$i].parameters[$j].description // empty" "$json_file")
                if [[ -z "$param_desc" ]]; then
                    debug_error "$function_name" "$ERR_APP_METADATA_MISSING" "launch_options[$i].parameters[$j] missing description"
                    return 1
                fi
                
                ((j++))
            done
        fi
        
        ((i++))
    done
    
    debug_log "$function_name" "✓ Parameter validation passed"
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