#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_COMMAND_LOADED" || return 0

window_command() {
    local function_name="window_command"
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
        echo "Error: Window subcommand required" >&2
        window_show_help
        return 1
    fi

    # Dispatch to appropriate handler
    case "$subcommand" in
        list)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/window/list.sh"
            window_list "${args[@]}"
            ;;
        status)
            # shellcheck source=status.sh
            source "${LIB_DIR}/commands/window/status.sh"
            window_status "${args[@]}"
            ;;
        close)
            # shellcheck source=close.sh
            source "${LIB_DIR}/commands/window/close.sh"
            window_close "${args[@]}"
            ;;
        open)
            # shellcheck source=open.sh
            source "${LIB_DIR}/commands/window/open.sh"
            window_open "${args[@]}"
            ;;
        move)
            # shellcheck source=move.sh
            source "${LIB_DIR}/commands/window/move.sh"
            window_move "${args[@]}"
            ;;
        focus)
            # shellcheck source=focus.sh
            source "${LIB_DIR}/commands/window/focus.sh"
            window_focus "${args[@]}"
            ;;
        minimize)
            # shellcheck source=minimize.sh
            source "${LIB_DIR}/commands/window/minimize.sh"
            window_minimize "${args[@]}"
            ;;
        *)
            echo "Error: Unknown window subcommand: $subcommand" >&2
            window_show_help
            return 1
            ;;
    esac
}

window_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall window <subcommand> [options]

Window Subcommands:
  list [workspace]                     List tracked windows
  status <window-name>                 Show window details
  close <window-name>                  Close a specific window
  open <window-name>                   Re-open a previously closed window
  move <window-name> <screen> <pos>    Move/reposition a window
  focus <window-name>                  Bring window to front
  minimize <window-name>               Minimize window

Examples:
  kdoitall window list
  kdoitall window list dev-env
  kdoitall window status dev-env-firefox-1
  kdoitall window close dev-env-firefox-1
  kdoitall window open dev-env-firefox-1
  kdoitall window move dev-env-firefox-1 1 Fullscreen
  kdoitall window focus dev-env-firefox-1
  kdoitall window minimize dev-env-firefox-1

EOF
}
