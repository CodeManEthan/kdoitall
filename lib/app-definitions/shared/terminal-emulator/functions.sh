#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SHARED_TERMINAL_EMULATOR_LOADED" || return 0

# shellcheck source=lib/core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=lib/db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=lib/db/terminal-emulator.sh
source "${LIB_DIR}/db/terminal-emulator.sh"

# Module-level variables set by each terminal_* function before calling
# execute_launch_window. The _launch_terminal_with_command helper reads these.
_TERM_EXECUTABLE=""
_TERM_EXEC_FLAG=""
_TERM_BASH_COMMAND=""

_launch_terminal_with_command() {
    local _unused="$1"

    if [[ -z "$_TERM_EXEC_FLAG" || "$_TERM_EXEC_FLAG" == "NULL" ]]; then
        "$_TERM_EXECUTABLE" bash -c "$_TERM_BASH_COMMAND" > /dev/null 2>&1 & disown
    else
        # exec_flag may be multi-word (e.g., "start --")
        # shellcheck disable=SC2086
        "$_TERM_EXECUTABLE" $_TERM_EXEC_FLAG bash -c "$_TERM_BASH_COMMAND" > /dev/null 2>&1 & disown
    fi
}

_get_terminal_launch_context() {
    local app_id="$1"
    local function_name="_get_terminal_launch_context"

    debug_function_enter "$function_name" "$@"

    local launch_properties=""
    launch_properties=$(db_get_app_launch_properties "$app_id")

    if [[ -z "$launch_properties" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    local class="" launch_mode=""
    IFS='|' read -r class _ launch_mode _ <<< "$launch_properties"

    if [[ -z "$launch_mode" ]]; then
        launch_mode="$LAUNCH_MODE_UNKNOWN"
    fi

    local exec_flag=""
    exec_flag=$(db_get_terminal_exec_flag "$app_id") || exec_flag="-e"

    local terminal_command=""
    terminal_command=$(db_get_terminal_command "$app_id")

    if [[ -z "$terminal_command" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "No terminal command found for: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_function_exit "$function_name"
    echo "${class}|${launch_mode}|${exec_flag}|${terminal_command}"
    return 0
}

terminal_run_command_in_directory() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local directory="$7"
    local command="$8"
    local function_name="terminal_run_command_in_directory"

    debug_function_enter "$function_name" "$@"

    validate_directory_exists "$directory" || return 1

    local context=""
    context=$(_get_terminal_launch_context "$app_id") || return 1

    local class="" launch_mode="" exec_flag="" terminal_command=""
    IFS='|' read -r class launch_mode exec_flag terminal_command <<< "$context"

    # The directory is quoted with %q so any character in it stays part of
    # the path. The command runs as a command: that is what this function is for.
    local quoted_directory=""
    printf -v quoted_directory '%q' "$directory"

    _TERM_EXECUTABLE="$terminal_command"
    _TERM_EXEC_FLAG="$exec_flag"
    _TERM_BASH_COMMAND="cd ${quoted_directory} && ${command}; exec bash"

    local window_title_pattern=""
    window_title_pattern=$(basename "$directory")

    execute_launch_window \
        "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" \
        "$launch_mode" "$LAUNCH_TYPE_TERMINAL" "_launch_terminal_with_command" \
        "$class" "$window_title_pattern" "" ""

    debug_function_exit "$function_name"
}

terminal_run_script() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local script_path="$7"
    local function_name="terminal_run_script"

    debug_function_enter "$function_name" "$@"

    validate_file_exists "$script_path" || return 1

    local context=""
    context=$(_get_terminal_launch_context "$app_id") || return 1

    local class="" launch_mode="" exec_flag="" terminal_command=""
    IFS='|' read -r class launch_mode exec_flag terminal_command <<< "$context"

    local quoted_script_path=""
    printf -v quoted_script_path '%q' "$script_path"

    _TERM_EXECUTABLE="$terminal_command"
    _TERM_EXEC_FLAG="$exec_flag"
    _TERM_BASH_COMMAND="${quoted_script_path}; exec bash"

    local window_title_pattern=""
    window_title_pattern=$(basename "$script_path")

    execute_launch_window \
        "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" \
        "$launch_mode" "$LAUNCH_TYPE_TERMINAL" "_launch_terminal_with_command" \
        "$class" "$window_title_pattern" "" ""

    debug_function_exit "$function_name"
}

terminal_launch_dev_server() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local directory="$7"
    local venv_path="$8"
    local server_command="$9"
    local function_name="terminal_launch_dev_server"

    debug_function_enter "$function_name" "$@"

    validate_directory_exists "$directory" || return 1

    local context=""
    context=$(_get_terminal_launch_context "$app_id") || return 1

    local class="" launch_mode="" exec_flag="" terminal_command=""
    IFS='|' read -r class launch_mode exec_flag terminal_command <<< "$context"

    # Paths are quoted with %q so any character in them stays part of the
    # path. The server command runs as a command: that is what this
    # function is for.
    local quoted_directory=""
    printf -v quoted_directory '%q' "$directory"
    local bash_command="cd ${quoted_directory}"

    if [[ -n "$venv_path" ]]; then
        local quoted_venv_path=""
        printf -v quoted_venv_path '%q' "$venv_path"
        bash_command="${bash_command} && source ${quoted_venv_path}"
    fi

    bash_command="${bash_command} && ${server_command}"

    _TERM_EXECUTABLE="$terminal_command"
    _TERM_EXEC_FLAG="$exec_flag"
    _TERM_BASH_COMMAND="$bash_command"

    local window_title_pattern=""
    window_title_pattern=$(basename "$directory")

    execute_launch_window \
        "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" \
        "$launch_mode" "$LAUNCH_TYPE_TERMINAL" "_launch_terminal_with_command" \
        "$class" "$window_title_pattern" "" ""

    debug_function_exit "$function_name"
}
