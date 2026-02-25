#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DEFS_DIR="${PROJECT_DIR}/lib/app-definitions/apps"

# --- Utility Functions ---

print_error() {
    echo -e "${RED}Error:${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo -e "${CYAN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

prompt_input() {
    local prompt_text="$1"
    local variable_name="$2"
    local default_value="${3:-}"
    local result=""

    if [[ -n "$default_value" ]]; then
        read -rp "$(echo -e "${BOLD}${prompt_text}${NC} [${default_value}]: ")" result
        if [[ -z "$result" ]]; then
            result="$default_value"
        fi
    else
        while [[ -z "$result" ]]; do
            read -rp "$(echo -e "${BOLD}${prompt_text}${NC}: ")" result
            if [[ -z "$result" ]]; then
                print_error "Value cannot be empty."
            fi
        done
    fi

    printf -v "$variable_name" '%s' "$result"
}

# --- Validation Functions ---

validate_app_id() {
    local app_id="$1"

    if [[ ! "$app_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        print_error "Invalid app_id '${app_id}'. Use alphanumeric characters, dots, hyphens, or underscores."
        return 1
    fi
    return 0
}

validate_suffix() {
    local suffix="$1"

    if [[ ! "$suffix" =~ ^[a-z][a-z0-9_]*$ ]]; then
        print_error "Invalid suffix '${suffix}'. Must match ^[a-z][a-z0-9_]*$ (e.g., 'window', 'workspace_window')."
        return 1
    fi
    return 0
}

validate_param_name() {
    local name="$1"

    if [[ ! "$name" =~ ^[A-Z][a-zA-Z0-9_]*$ ]]; then
        print_error "Invalid parameter name '${name}'. Must be PascalCase (e.g., 'Path', 'DirectoryPath')."
        return 1
    fi
    return 0
}

pascal_to_snake() {
    local input="$1"

    echo "$input" | sed -E 's/([A-Z])/_\L\1/g' | sed 's/^_//'
}

sanitize_for_function_name() {
    local input="$1"

    echo "$input" | tr '.-' '_'
}

# --- Generation Functions ---

generate_file_header() {
    local guard_name="$1"

    cat <<HEADER
#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_${guard_name}_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "\${LIB_DIR}/core/core.sh"
# shellcheck source=lib/app-definitions/loader.sh
source "\${LIB_DIR}/app-definitions/loader.sh"
# shellcheck source=lib/db/app.sh
source "\${LIB_DIR}/db/app.sh"

load_app_metadata "\${BASH_SOURCE[0]%/*}"
HEADER
}

generate_private_launcher() {
    local func_prefix="$1"
    local terminal_command="$2"

    cat <<LAUNCHER

_launch_${func_prefix}() {
    local arg="\$1"

    # TODO: Implement launch command
    ${terminal_command} "\$arg" > /dev/null 2>&1 & disown
}
LAUNCHER
}

generate_public_function() {
    local func_prefix="$1"
    local suffix="$2"
    shift 2

    local full_function_name="launch_${func_prefix}_${suffix}"
    local param_index=6
    local param_locals=""
    local last_param_var=""

    # Build parameter local declarations
    while [[ $# -gt 0 ]]; do
        local snake_name=""
        snake_name=$(pascal_to_snake "$1")
        param_locals+="    local ${snake_name}=\"\$${param_index}\"\n"
        last_param_var="\$${snake_name}"
        param_index=$((param_index + 1))
        shift
    done

    # If no custom params, use empty string for the last arg
    if [[ -z "$last_param_var" ]]; then
        last_param_var='""'
    fi

    # Start function output
    echo ""
    echo "${full_function_name}() {"
    echo '    local workspace_name="$1"'
    echo '    local window_name="$2"'
    echo '    local desktop="$3"'
    echo '    local screen="$4"'
    echo '    local position="$5"'

    # Custom parameter locals
    if [[ -n "$param_locals" ]]; then
        echo -ne "$param_locals"
    fi

    cat <<BODY

    local window_title_pattern=""
    local function_name="${full_function_name}"

    debug_function_enter "\$function_name" "\$@"

    local launch_properties=""
    launch_properties=\$(db_get_app_launch_properties "\$APP_ID")

    if [[ -z "\$launch_properties" ]]; then
        debug_error "\$function_name" "\$ERR_APP_ID_INVALID" "Application not found: \$APP_ID"
        debug_function_exit "\$function_name"
        return 1
    fi

    local class=""
    local launch_mode=""
    IFS='|' read -r class _ launch_mode _ <<< "\$launch_properties"

    # TODO: Set window_title_pattern for window detection
    window_title_pattern=""

    execute_launch_window \\
    "\$workspace_name" "\$window_name" "\$APP_ID" "\$desktop" "\$screen" "\$position" "\$launch_mode" "\$LAUNCH_TYPE" "_launch_${func_prefix}" \\
    "\$class" "\$window_title_pattern" "" ${last_param_var}

    debug_function_exit "\$function_name"
}
BODY
}

generate_metadata_json() {
    local terminal_command="$1"
    local function_name="$2"
    local description="$3"
    shift 3

    # Build parameters array
    local params_json="[]"
    while [[ $# -ge 2 ]]; do
        local param_name="$1"
        local param_desc="$2"
        params_json=$(echo "$params_json" | jq \
            --arg name "$param_name" \
            --arg desc "$param_desc" \
            '. + [{"name": $name, "description": $desc}]')
        shift 2
    done

    # Build full metadata
    jq -n \
        --arg cmd "$terminal_command" \
        --arg fn "$function_name" \
        --arg desc "$description" \
        --argjson params "$params_json" \
        '{
            terminal_command: $cmd,
            launch_options: [
                {
                    function_name: $fn,
                    description: $desc,
                    parameters: $params
                }
            ]
        }'
}

append_launch_option_to_metadata() {
    local json_file="$1"
    local function_name="$2"
    local description="$3"
    shift 3

    # Build parameters array
    local params_json="[]"
    while [[ $# -ge 2 ]]; do
        local param_name="$1"
        local param_desc="$2"
        params_json=$(echo "$params_json" | jq \
            --arg name "$param_name" \
            --arg desc "$param_desc" \
            '. + [{"name": $name, "description": $desc}]')
        shift 2
    done

    # Append new launch option
    local updated=""
    updated=$(jq \
        --arg fn "$function_name" \
        --arg desc "$description" \
        --argjson params "$params_json" \
        '.launch_options += [{
            function_name: $fn,
            description: $desc,
            parameters: $params
        }]' "$json_file")

    echo "$updated" > "$json_file"
}

# --- Dependency Check ---

if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed. Install it with your package manager."
    exit 1
fi

# --- Main Script ---

echo ""
echo -e "${BOLD}=== kdoitall App Definition Generator ===${NC}"
echo ""

# Collect app_id
app_id="${1:-}"
if [[ -z "$app_id" ]]; then
    prompt_input "App ID (directory name, e.g., 'org.mozilla.firefox', 'code')" app_id
fi

validate_app_id "$app_id" || exit 1

app_dir="${APP_DEFS_DIR}/${app_id}"
functions_file="${app_dir}/functions.sh"
metadata_file="${app_dir}/metadata.json"
is_new_app=false

if [[ ! -d "$app_dir" ]]; then
    is_new_app=true
    print_info "Creating new app definition for '${app_id}'..."
else
    print_info "Adding function to existing app definition '${app_id}'..."
fi

# Sanitize app_id for use in bash function names (dots/hyphens -> underscores)
func_prefix=""
func_prefix=$(sanitize_for_function_name "$app_id")

echo ""

# Collect new-app-only inputs
terminal_command=""
guard_name=""

if [[ "$is_new_app" == true ]]; then
    prompt_input "Terminal command (e.g., 'firefox', 'code')" terminal_command

    # Derive guard name from app_id: uppercase, dots/hyphens to underscores
    guard_name="${app_id^^}"
    guard_name="${guard_name//./_}"
    guard_name="${guard_name//-/_}"
fi

# Collect function suffix
echo ""
print_info "The public function will be named: launch_${func_prefix}_<suffix>"
prompt_input "Function suffix (e.g., 'window', 'workspace_window')" suffix
validate_suffix "$suffix" || exit 1

full_function_name="launch_${func_prefix}_${suffix}"

# Check for duplicate function in existing app
if [[ "$is_new_app" == false ]]; then
    existing_function=""
    existing_function=$(jq -r --arg fn "$full_function_name" \
        '.launch_options[] | select(.function_name == $fn) | .function_name' \
        "$metadata_file" 2>/dev/null || true)

    if [[ -n "$existing_function" ]]; then
        print_error "Function '${full_function_name}' already exists in ${metadata_file}"
        exit 1
    fi
fi

# Collect description
echo ""
prompt_input "Description (e.g., 'Open URL', 'Open directory or file')" description

# Collect parameters
echo ""
param_count=""
prompt_input "Number of custom parameters (beyond the standard 5)" param_count "0"

if [[ ! "$param_count" =~ ^[0-9]+$ ]]; then
    print_error "Parameter count must be a non-negative integer."
    exit 1
fi

# Arrays for parameter data
param_names=()
param_descs=()
param_snake_names=()

i=1
while [[ $i -le $param_count ]]; do
    echo ""
    print_info "Parameter ${i} of ${param_count}:"

    p_name=""
    prompt_input "  Parameter name (PascalCase, e.g., 'Path', 'DirectoryPath')" p_name
    validate_param_name "$p_name" || exit 1

    p_desc=""
    prompt_input "  Parameter description" p_desc

    param_names+=("$p_name")
    param_descs+=("$p_desc")
    param_snake_names+=("$(pascal_to_snake "$p_name")")

    i=$((i + 1))
done

# --- Confirmation Summary ---

echo ""
echo -e "${BOLD}=== Summary ===${NC}"
echo -e "  App ID:          ${CYAN}${app_id}${NC}"
if [[ "$is_new_app" == true ]]; then
    echo -e "  Terminal command: ${CYAN}${terminal_command}${NC}"
    echo -e "  Guard name:      ${CYAN}_KDOITALL_${guard_name}_LOADED${NC}"
fi
echo -e "  Function name:   ${CYAN}${full_function_name}${NC}"
echo -e "  Description:     ${CYAN}${description}${NC}"

if [[ ${#param_names[@]} -gt 0 ]]; then
    echo -e "  Parameters:"
    j=0
    while [[ $j -lt ${#param_names[@]} ]]; do
        echo -e "    - ${CYAN}${param_names[$j]}${NC} (${param_descs[$j]})"
        j=$((j + 1))
    done
fi

echo ""
confirm=""
read -rp "$(echo -e "${BOLD}Generate files? [Y/n]:${NC} ")" confirm
if [[ "$confirm" =~ ^[Nn] ]]; then
    print_warning "Aborted."
    exit 0
fi

# --- Generate Files ---

# Build param name args for generate_public_function
public_func_args=()
for name in "${param_names[@]+"${param_names[@]}"}"; do
    public_func_args+=("$name")
done

# Build param pairs for metadata functions (name desc name desc ...)
metadata_param_args=()
j=0
while [[ $j -lt ${#param_names[@]} ]]; do
    metadata_param_args+=("${param_names[$j]}" "${param_descs[$j]}")
    j=$((j + 1))
done

if [[ "$is_new_app" == true ]]; then
    # --- New App ---
    mkdir -p "$app_dir"

    # Generate functions.sh
    {
        generate_file_header "$guard_name"
        generate_private_launcher "$func_prefix" "$terminal_command"
        generate_public_function "$func_prefix" "$suffix" "${public_func_args[@]+"${public_func_args[@]}"}"
    } > "$functions_file"

    chmod +x "$functions_file"

    # Generate metadata.json
    generate_metadata_json "$terminal_command" "$full_function_name" "$description" \
        ${metadata_param_args[@]+"${metadata_param_args[@]}"} > "$metadata_file"

    echo ""
    print_success "Created new app definition:"
    print_success "  ${functions_file}"
    print_success "  ${metadata_file}"
else
    # --- Existing App ---

    # Append public function to functions.sh
    generate_public_function "$func_prefix" "$suffix" "${public_func_args[@]+"${public_func_args[@]}"}" >> "$functions_file"

    # Append launch option to metadata.json
    append_launch_option_to_metadata "$metadata_file" "$full_function_name" "$description" \
        ${metadata_param_args[@]+"${metadata_param_args[@]}"}

    echo ""
    print_success "Updated existing app definition:"
    print_success "  Appended function to ${functions_file}"
    print_success "  Added launch option to ${metadata_file}"
fi

echo ""
print_warning "TODO: Review the generated files and update:"
print_warning "  - The private launcher command in _launch_${func_prefix}()"
print_warning "  - The window_title_pattern in ${full_function_name}()"
echo ""
