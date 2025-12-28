#!/bin/bash

check_and_set_guard "_KDOITALL_FIREFOX_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"

launch_firefox_window() {
    local window_name="$1"
    local desktop="$2"
    local screen="$3"
    local position="$4"
    local url="$5"

    local launch_command
    local function_name="launch_firefox_window"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    launch_command="firefox --new-window \"$url\" &"

    launch_window "$window_name" "$desktop" "$screen" "$position" "$launch_command"
}

launch_firefox_tab() {
    local window_name="$1"
    local tab_name="$2"
    local desktop="$3"
    local screen="$4"
    local position="$5"
    local url="$6"

    local launch_command
    local function_name="launch_firefox_tab"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    launch_command="firefox --new-tab \"$url\" &"

    launch_window "$window_name" "$tab_name" "$desktop" "$screen" "$position" "$launch_command"
}