#!/bin/bash

check_and_set_guard "_KDOITALL_CODE_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

# ============================================================================
# Application Metadata
# ============================================================================

# shellcheck disable=SC2034
# Command to validate terminal availability
TERMINAL_COMMAND="code"

# shellcheck disable=SC2034
# Launch options with user-friendly descriptions
declare -A LAUNCH_OPTIONS=(
    ["launch_vscode_window"]="Open directory or file"
    ["launch_vscode_workspace_window"]="Open .code-workspace file"
)

# ============================================================================
# Script-Global Variables
# ============================================================================

# Launch configuration variables (script-global, not exported)
launch_mode="$LAUNCH_MODE_UNIQUE"
launch_type="$LAUNCH_TYPE_TERMINAL"
class="code"
app_id="code"

# ============================================================================
# Launch Functions
# ============================================================================

launch_vscode_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local directory_path="$6"
    
    local launch_command=""
    local window_title=""
    local function_name="launch_vscode_window"

    debug_function_enter "$function_name" "$@"

    directory_path=$(safe_directory "$directory_path") || return 1
    
    launch_mode="$LAUNCH_MODE_UNIQUE"
    launch_type="$LAUNCH_TYPE_TERMINAL"
    launch_command="code --new-window \"$directory_path\" &"

    local directory=""
    directory=$(basename "$directory_path")
    window_title="$directory - Visual Studio Code"
    window_title=$(safe_name "$window_title")

    execute_launch_window \
    "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" "$launch_mode" "$launch_type" "$launch_command" \
    --window-title "$window_title"

    debug_function_exit "$function_name"
}

launch_vscode_workspace_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local workspace_path="$6"

    local launch_command=""
    local window_title=""
    local function_name="launch_vscode_workspace_window"

    debug_function_enter "$function_name" "$@"

    workspace_path=$(safe_file "$workspace_path") || return 1

    launch_command="code --new-window \"$workspace_path\" &"

    local workspace=""
    workspace=$(basename "$workspace_path" .code-workspace)
    window_title="$workspace (Workspace) - Visual Studio Code"
    window_title=$(safe_name "$window_title")

    execute_launch_window \
    "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" "$launch_mode" "$launch_type" "$launch_command" \
    --window-title "$window_title"

    debug_function_exit "$function_name"
}

