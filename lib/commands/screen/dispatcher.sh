#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SCREEN_COMMAND_LOADED" || return 0

screen_command() {
    local function_name="screen_command"
    local subcommand=""
    local -a args=()

    # Parse arguments, filtering out global flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|--info)
                shift
                ;;
            *)
                if [[ -z "$subcommand" ]]; then
                    subcommand="$1"
                    shift
                else
                    args+=("$1")
                    shift
                fi
                ;;
        esac
    done

    debug_log "$function_name" "subcommand='$subcommand', args=(${args[*]:-}), args count=${#args[@]}"

    # Validate subcommand provided
    if [[ -z "$subcommand" ]]; then
        echo "Error: Screen subcommand required" >&2
        screen_show_help
        return 1
    fi

    # Dispatch to appropriate handler
    case "$subcommand" in
        list)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/screen/list.sh"
            screen_list "${args[@]}"
            ;;
        alias)
            # shellcheck source=alias.sh
            source "${LIB_DIR}/commands/screen/alias.sh"
            screen_alias "${args[@]}"
            ;;
        *)
            echo "Error: Unknown screen subcommand: $subcommand" >&2
            screen_show_help
            return 1
            ;;
    esac
}

screen_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall screen <subcommand> [options]

Screen Subcommands:
  list                        List detected screens with aliases
  alias <alias> <target>      Set a screen alias (target = number or name)
  alias remove <alias>        Remove a screen alias

Examples:
  kdoitall screen list
  kdoitall screen alias laptop eDP-1
  kdoitall screen alias primary 1
  kdoitall screen alias remove laptop

EOF
}
