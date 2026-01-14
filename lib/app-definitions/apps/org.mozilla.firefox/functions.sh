#!/bin/bash

check_and_set_guard "_KDOITALL_FIREFOX_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

# Load metadata from JSON into global variables
# This happens once when the file is sourced
_load_app_metadata() {
    local app_dir="${BASH_SOURCE[0]%/*}"
    local json_file="$app_dir/metadata.json"
    
    # shellcheck disable=SC2034
    TERMINAL_COMMAND=$(jq -r '.terminal_command' "$json_file")
    # shellcheck disable=SC2034
    APP_ID=$(jq -r '.app_id' "$json_file")
    # shellcheck disable=SC2034
    APP_CLASS=$(jq -r '.app_class // empty' "$json_file")
    # shellcheck disable=SC2034
    LAUNCH_MODE=$(jq -r '.launch_mode' "$json_file")
    # shellcheck disable=SC2034
    LAUNCH_TYPE=$(jq -r '.launch_type' "$json_file")
}

_load_app_metadata

launch_firefox_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local url="$6"
    local launch_command=""
    local window_title_pattern=""
    local function_name="launch_firefox_window"

    debug_function_enter "$function_name" "$@"

    window_title_pattern=" — Mozilla Firefox"
    
    launch_command="firefox --new-window \"$url\" &"

    execute_launch_window \
    "$workspace_name" "$window_name" "$APP_ID" "$desktop" "$screen" "$position" "$LAUNCH_MODE" "$LAUNCH_TYPE" "$launch_command" \
    "$APP_CLASS" "$window_title_pattern" ""

    debug_function_exit "$function_name"
}