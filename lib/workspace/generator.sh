#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_GENERATE_LOADED" || return 0

# shellcheck source=../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../db/window-definitions.sh
source "${LIB_DIR}/db/window-definitions.sh"
# shellcheck source=../utils/workspace-validators.sh
source "${LIB_DIR}/utils/workspace-validators.sh"

# Refuse any workspace entry whose fields could be read as shell code by the
# generated script. The entry points validate these already; this runs
# again here because every path that writes a script passes through the
# generator. Identifiers are written bare (the launch function as a command
# word, the position as a variable name), so they must be plain identifiers.
# Values are quoted with %q when written, but a '|' or newline in params
# would already have corrupted the record they came in.
_validate_workspace_entries() {
    local workspace_name="$1"
    local function_name="_validate_workspace_entries"

    if ! validate_workspace_name "$workspace_name" 3>/dev/null; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Refusing to generate a script for workspace: $workspace_name"
        return 1
    fi

    local app_config="" app_id="" window_name="" launch_function=""
    local desktop="" screen="" position="" parameters=""
    for app_config in "${WORKSPACE_APPS[@]}"; do
        # A newline would end the record early, so check the whole record
        # for control characters (tabs separate params) before splitting it.
        if ! validate_params "${app_config//|/}"; then
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Refusing to generate a script: a window entry contains a control character"
            return 1
        fi

        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"

        if ! validate_window_name "$window_name" 3>/dev/null; then
            debug_error "$function_name" "$ERR_INVALID_WINDOW_NAME" "Refusing to generate a script with window name: $window_name"
            return 1
        fi
        if ! validate_app_id_format "$app_id"; then
            return 1
        fi
        if ! is_shell_identifier "$launch_function"; then
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Refusing to generate a script with launch function: $launch_function"
            return 1
        fi
        if ! is_shell_identifier "$position"; then
            debug_error "$function_name" "$ERR_INVALID_POSITION" "Refusing to generate a script with position: $position"
            return 1
        fi
        if ! validate_params "$parameters"; then
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Refusing to generate a script for window '$window_name': params contain '|' or a control character"
            return 1
        fi
    done

    return 0
}

generate_workspace_scripts() {
    local workspace_name="$1"
    local function_name="generate_workspace_scripts"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    local workspace_script="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}.sh"

    # Ensure workspace scripts directory exists
    if ! mkdir -p "$WORKSPACE_SCRIPTS_DIR"; then
        debug_error "$function_name" "Failed to create workspace scripts directory"
        debug_function_exit "$function_name"
        return 1
    fi

    # Generate combined workspace script
    if ! generate_workspace_script "$workspace_name" "$workspace_script"; then
        debug_error "$function_name" "Failed to generate workspace script"
        debug_function_exit "$function_name"
        return 1
    fi

    # Store window definitions in database for re-open support
    if ! store_window_definitions "$workspace_name"; then
        debug_error "$function_name" "Failed to store window definitions"
        debug_function_exit "$function_name"
        return 1
    fi

    # Make script executable
    chmod +x "$workspace_script"

    debug_log "$function_name" "Successfully generated workspace script"
    debug_function_exit "$function_name"
    return 0
}

generate_workspace_script() {
    local workspace_name="$1"
    local script_path="$2"
    local guard_name=""
    local open_func_name=""
    local function_name="generate_workspace_script"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$script_path" "script_path" || return 1

    # Check every entry before anything else runs: before the app-file loop's
    # DB lookups and before a byte of the script is written.
    if ! _validate_workspace_entries "$workspace_name"; then
        debug_function_exit "$function_name"
        return 1
    fi

    # Generate names from workspace name
    # Convert to uppercase and replace hyphens with underscores
    guard_name="_KDOITALL_WORKSPACE_${workspace_name^^}_LOADED"
    guard_name="${guard_name//-/_}"

    open_func_name="open_workspace_${workspace_name//-/_}"

    # Check if array is empty
    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        debug_error "$function_name" "No applications configured for workspace"
        debug_function_exit "$function_name"
        return 1
    fi

    # Start building script with header
    cat > "$script_path" << 'EOF_HEADER'
#!/bin/bash

# This file was generated by kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# You are free to modify this file for your own use.

check_and_set_guard "GUARD_NAME" || return 0

EOF_HEADER

    # Replace guard name placeholder
    sed -i "s/GUARD_NAME/$guard_name/g" "$script_path"

    # Collect unique app files that need sourcing (terminal launch only)
    local -A app_files_to_source
    local has_app_files=false
    for app_config in "${WORKSPACE_APPS[@]}"; do
        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"

        # Check if it's a terminal launch by checking if launch_function is NOT launch_by_app_id
        if [[ "$launch_function" != "launch_by_app_id" ]]; then
            if [[ "$launch_function" == terminal_* ]]; then
                # Shared terminal emulator function
                app_files_to_source["${LIB_DIR}/app-definitions/shared/terminal-emulator/functions.sh"]=1
                has_app_files=true
            else
                local app_directory_path=""
                app_directory_path=$(db_get_app_directory_path "$app_id")
                if [[ -n "$app_directory_path" ]]; then
                    app_files_to_source["${app_directory_path}/functions.sh"]=1
                    has_app_files=true
                fi
            fi
        fi
    done

    # Add source statements
    if [[ "$has_app_files" == true ]]; then
        echo "# Source required application files" >> "$script_path"
        for app_file in "${!app_files_to_source[@]}"; do
            echo "# shellcheck source=${app_file#"${KDOITALL_ROOT}"/}" >> "$script_path"
            printf 'source %q\n' "$app_file" >> "$script_path"
        done
        echo "" >> "$script_path"
    fi

    # Source core for launch functions
    echo "# shellcheck disable=SC1091" >> "$script_path"
    echo "source \"\${LIB_DIR}/core/core.sh\"" >> "$script_path"
    echo "" >> "$script_path"

    # === Generate open function ===
    echo "$open_func_name() {" >> "$script_path"
    echo "    debug_log \"Opening workspace: $workspace_name\"" >> "$script_path"
    echo "" >> "$script_path"

    # Every value is written with %q, so the script hands the launch function
    # exactly the stored string as one argument, never something the shell
    # expands. The launch function and the position were checked above to be
    # plain identifiers; the position is written as a variable reference.
    for app_config in "${WORKSPACE_APPS[@]}"; do
        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"

        echo "    # Launch: $window_name ($app_id)" >> "$script_path"

        local -a call_args=()
        if [[ "$launch_function" == "launch_by_app_id" ]]; then
            call_args=("$workspace_name" "$window_name" "$app_id" "$desktop" "$screen")
            _write_launch_call "$script_path" "$launch_function" "$position" \
                "${#call_args[@]}" "${call_args[@]}"
        elif [[ "$launch_function" == terminal_* ]]; then
            # Shared terminal function: app_id, then one argument per
            # tab-separated param. Empty fields are kept: "dir<TAB><TAB>cmd"
            # is three arguments with an empty middle one.
            local -a param_array=()
            if [[ -n "$parameters" ]]; then
                readarray -td $'\t' param_array < <(printf '%s\t' "$parameters")
            fi
            call_args=("$workspace_name" "$window_name" "$app_id" "$desktop" "$screen")
            _write_launch_call "$script_path" "$launch_function" "$position" \
                "${#call_args[@]}" "${call_args[@]}" "${param_array[@]}"
        else
            # Per-app terminal function: the params as one string, tabs and all
            call_args=("$workspace_name" "$window_name" "$desktop" "$screen")
            _write_launch_call "$script_path" "$launch_function" "$position" \
                "${#call_args[@]}" "${call_args[@]}" "$parameters"
        fi
    done

    echo "}" >> "$script_path"

    debug_log "$function_name" "Generated workspace script: $script_path"
    debug_function_exit "$function_name"
    return 0
}

# Append one launch call to the script:
#   _write_launch_call <script> <function> <position> <n> <arg>... [<param>...]
# The first n args go before the position, which is written as "$POSITION";
# the rest are params and go after it. Every value is quoted with %q.
_write_launch_call() {
    local script_path="$1"
    local launch_function="$2"
    local position="$3"
    local leading_count="$4"
    shift 4

    local line="    ${launch_function}"
    local quoted=""
    local i=0
    for (( i = 0; i < leading_count; i++ )); do
        printf -v quoted '%q' "$1"
        line+=" ${quoted}"
        shift
    done
    line+=" \"\$${position}\""
    while [[ $# -gt 0 ]]; do
        printf -v quoted '%q' "$1"
        line+=" ${quoted}"
        shift
    done

    printf '%s\n\n' "$line" >> "$script_path"
}

load_workspace_apps_array() {
    local workspace_name="$1"
    local function_name="load_workspace_apps_array"

    debug_function_enter "$function_name" "$@"

    local window_defs=""
    window_defs=$(db_list_window_definitions "$workspace_name")

    if [[ -z "$window_defs" ]]; then
        debug_log "$function_name" "No window definitions found for workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    fi

    while IFS='|' read -r window_name _ app_id launch_function desktop screen position parameters _; do
        [[ -z "$window_name" ]] && continue
        WORKSPACE_APPS+=("${app_id}|${window_name}|${launch_function}|${desktop}|${screen}|${position}|${parameters}")
    done <<< "$window_defs"

    debug_log "$function_name" "Loaded ${#WORKSPACE_APPS[@]} window definitions"
    debug_function_exit "$function_name"
    return 0
}

store_window_definitions() {
    local workspace_name="$1"
    local function_name="store_window_definitions"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    # Clear any existing definitions for this workspace (handles re-creation)
    db_delete_window_definitions_for_workspace "$workspace_name"

    local display_order=0
    for app_config in "${WORKSPACE_APPS[@]}"; do
        IFS='|' read -r app_id window_name launch_function \
                        desktop screen position parameters <<< "$app_config"

        db_add_window_definition \
            "$window_name" "$workspace_name" "$app_id" "$launch_function" \
            "$desktop" "$screen" "$position" "$parameters" "$display_order"

        display_order=$((display_order + 1))
    done

    debug_log "$function_name" "Stored $display_order window definitions for workspace: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}
