#!/bin/bash

check_and_set_guard "_KDOITALL_VSCODE_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

launch_vscode_window() {
    local window_name="$1"
    local desktop="$2"
    local screen="$3"
    local position="$4"
    local directory_path="$5"
    
    local class=""
    local launch_mode=""
    local launch_command=""
    local window_title=""
    local function_name="launch_vscode_window"

    debug_function_enter "$function_name" "$@"

    directory_path=$(safe_directory "$directory_path") || return 1
    
    class="code"
    launch_mode="$LAUNCH_MODE_UNIQUE"
    launch_command="code --new-window \"$directory_path\" &"

    local directory
    directory=$(basename "$directory_path")
    window_title="$directory - Visual Studio Code"
    window_title=$(safe_name "$window_title")

    launch_window "$window_name" "$class" "$desktop" "$screen" "$position" "$launch_mode" "$launch_command" --window-title "$window_title"

    debug_function_exit "$function_name"
}

launch_vscode_workspace_window() {
    local window_name="$1"
    local desktop="$2"
    local screen="$3"
    local position="$4"
    local workspace_path="$5"

    local class
    local launch_mode
    local launch_command
    local window_title
    local function_name="launch_vscode_workspace_window"

    debug_function_enter "$function_name" "$@"

    workspace_path=$(safe_file "$workspace_path") || return 1

    class="code"
    launch_mode="$LAUNCH_MODE_UNIQUE"
    launch_command="code --new-window \"$workspace_path\" &"

    local workspace
    workspace=$(basename "$workspace_path" .code-workspace)
    window_title="$workspace (Workspace) - Visual Studio Code"
    window_title=$(safe_name "$window_title")

    launch_window "$window_name" "$class" "$desktop" "$screen" "$position" "$launch_mode" "$launch_command" --window-title "$window_title"

    debug_function_exit "$function_name"
}

