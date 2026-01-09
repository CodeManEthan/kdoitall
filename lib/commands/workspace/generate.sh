#!/bin/bash

check_and_set_guard "_KDOITALL_WORKSPACE_GENERATE_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../../db/app-registry.sh
source "${LIB_DIR}/db/app-registry.sh"

generate_workspace_scripts() {
    local workspace_name="$1"
    # apps_array_ref="$2"
    local function_name="generate_workspace_scripts"

    debug_function_enter "$function_name" "$@"

    validate_name_ref_parameter_pass "$2" "apps_array_ref" || return 1
    # shellcheck disable=SC2034
    local -n apps_array_ref="$2"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    local open_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
    local close_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh"

    # Ensure workspace scripts directory exists
    if ! mkdir -p "$WORKSPACE_SCRIPTS_DIR"; then
        debug_error "$function_name" "Failed to create workspace scripts directory"
        debug_function_exit "$function_name"
        return 1
    fi

    # Generate open script
    if ! generate_open_script "$workspace_name" "$open_script" apps_array_ref; then
        debug_error "$function_name" "Failed to generate open script"
        debug_function_exit "$function_name"
        return 1
    fi

    # Generate close script
    if ! generate_close_script "$workspace_name" "$close_script" apps_array_ref; then
        debug_error "$function_name" "Failed to generate close script"
        debug_function_exit "$function_name"
        return 1
    fi

    # Make scripts executable
    chmod +x "$open_script"
    chmod +x "$close_script"

    debug_log "$function_name" "Successfully generated workspace scripts"
    debug_function_exit "$function_name"
    return 0
}

generate_open_script() {
    local workspace_name="$1"
    local script_path="$2"
    # apps_ref="$3"
    local guard_name=""
    local function_name="generate_open_script"

    debug_function_enter "$function_name" "$@"

    validate_name_ref_parameter_pass "$3" "apps_ref" || return 1
    local -n apps_ref="$3"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$script_path" "script_path" || return 1

    # Generate guard name from workspace name
    # Convert to uppercase and replace hyphens with underscores
    guard_name="_KDOITALL_WORKSPACE_${workspace_name^^}_OPEN_LOADED"
    guard_name="${guard_name//-/_}"

    # Check if array is empty
    if [[ ${#apps_ref[@]} -eq 0 ]]; then
        debug_error "$function_name" "No applications configured for workspace"
        debug_function_exit "$function_name"
        return 1
    fi

    # Start building script with header
    cat > "$script_path" << 'EOF_HEADER'
#!/bin/bash

check_and_set_guard "GUARD_NAME" || return 0

EOF_HEADER

    # Replace guard name placeholder
    sed -i "s/GUARD_NAME/$guard_name/g" "$script_path"

    # Collect unique app files that need sourcing (terminal launch only)
    declare -A app_files_to_source
    for app_config in "${apps_ref[@]}"; do
        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"

        # Check if it's a terminal launch by checking if launch_function is NOT launch_by_app_id
        if [[ "$launch_function" != "launch_by_app_id" ]]; then
            local app_file_path=""
            app_file_path=$(db_get_app_file_path "$app_id")
            if [[ -n "$app_file_path" ]]; then
                app_files_to_source["$app_file_path"]=1
            fi
        fi
    done

    # Add source statements
    if [[ -v app_files_to_source && ${#app_files_to_source[@]} -gt 0 ]]; then
        echo "" >> "$script_path"
        echo "# Source required application files" >> "$script_path"
        for app_file in "${!app_files_to_source[@]}"; do
            echo "# shellcheck source=${app_file#"${KDOITALL_ROOT}"/}" >> "$script_path"
            echo "source \"${app_file}\"" >> "$script_path"
        done
    fi

    # Add debug log
    echo "" >> "$script_path"
    echo "debug_log \"Opening workspace: $workspace_name\"" >> "$script_path"
    echo "" >> "$script_path"

    # Generate launch commands
    for app_config in "${apps_ref[@]}"; do
        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"

        echo "# Launch: $window_name ($app_id)" >> "$script_path"

        # Build launch command with parameters
        local params_str=""
        if [[ -n "$parameters" ]]; then
            params_str=" \"$parameters\""
        else
            params_str=" \"\""
        fi

        # Generate the function call
        # Note: Position needs to be prefixed with $ and quoted
        # launch_by_app_id needs app_id parameter, custom launchers don't
        if [[ "$launch_function" == "launch_by_app_id" ]]; then
            cat >> "$script_path" << EOF
$launch_function "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "\$$position"$params_str

EOF
        else
            cat >> "$script_path" << EOF
$launch_function "$workspace_name" "$window_name" "$desktop" "$screen" "\$$position"$params_str

EOF
        fi
    done

    debug_log "$function_name" "Generated open script: $script_path"
    debug_function_exit "$function_name"
    return 0
}

generate_close_script() {
    local workspace_name="$1"
    local script_path="$2"
    # apps_ref="$3"
    local guard_name=""
    local function_name="generate_close_script"

    debug_function_enter "$function_name" "$@"

    validate_name_ref_parameter_pass "$3" "apps_ref" || return 1
    local -n apps_ref="$3"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$script_path" "script_path" || return 1    

    # Generate guard name from workspace name
    # Convert to uppercase and replace hyphens with underscores
    guard_name="_KDOITALL_WORKSPACE_${workspace_name^^}_CLOSE_LOADED"
    guard_name="${guard_name//-/_}"

    # Check if array is empty
    if [[ ${#apps_ref[@]} -eq 0 ]]; then
        debug_error "$function_name" "No applications configured for workspace"
        debug_function_exit "$function_name"
        return 1
    fi

    # Build script with header
    cat > "$script_path" << 'EOF_HEADER'
#!/bin/bash

check_and_set_guard "GUARD_NAME" || return 0

# shellcheck disable=SC1091
source "${LIB_DIR}/core/core.sh"

debug_log "Closing workspace: WORKSPACE_NAME"

EOF_HEADER

    # Replace placeholders
    sed -i "s/GUARD_NAME/$guard_name/g" "$script_path"
    sed -i "s/WORKSPACE_NAME/$workspace_name/g" "$script_path"

    # Add close commands
    echo "" >> "$script_path"
    for app_config in "${apps_ref[@]}"; do
        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"
        echo "execute_close_window \"$window_name\"" >> "$script_path"
    done

    debug_log "$function_name" "Generated close script: $script_path"
    debug_function_exit "$function_name"
    return 0
}
