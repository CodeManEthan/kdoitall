#!/bin/bash

check_and_set_guard "_KDOITALL_FIREFOX_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

# ============================================================================
# Application Metadata
# ============================================================================

# shellcheck disable=SC2034
# Command to validate terminal availability
TERMINAL_COMMAND="firefox"

# shellcheck disable=SC2034
# Launch options with user-friendly descriptions
declare -A LAUNCH_OPTIONS=(
    ["launch_firefox_window"]="Open URL"
)

# ============================================================================
# Script-Global Variables
# ============================================================================

# Launch configuration variables (script-global, not exported)
launch_mode="$LAUNCH_MODE_MULTI"
launch_type="$LAUNCH_TYPE_TERMINAL"
class="org.mozilla.firefox"
app_id="org.mozilla.firefox"

# ============================================================================
# Launch Functions
# ============================================================================

launch_firefox_window() {
    local workspace_name="$1"
    local window_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local url="$6"
    local launch_command=""
    local window_title=""
    local function_name="launch_firefox_window"

    debug_function_enter "$function_name" "$@"

    window_title=" — Mozilla Firefox"
    
    launch_command="firefox --new-window \"$url\" &"

    execute_launch_window \
    "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" "$launch_mode" "$launch_type" "$launch_command" \
    "$class" "$window_title" ""

    debug_function_exit "$function_name"
}

#launch_firefox_tab() {
#    local window_name="$1"
#    local tab_name="$2"
#   local desktop="$3"
#   local screen="$4"
#   local position="$5"
#   local url="$6"

#    local launch_command
#    local function_name="launch_firefox_tab"

#    debug_function_enter "$function_name" "$@"

#    class="org.mozilla.firefox"
#    launch_command="firefox --new-tab \"$url\" &"

#    launch_window "$window_name" "$tab_name" "$class" "$desktop" "$screen" "$position" "$LAUNCH_MODE_MULTI" "$launch_command"

#    debug_function_exit "$function_name"
#}