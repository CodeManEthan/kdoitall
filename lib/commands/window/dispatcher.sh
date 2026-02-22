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
        list|ls)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/window/list.sh"
            window_list "${args[@]}"
            ;;
        status|st)
            # shellcheck source=status.sh
            source "${LIB_DIR}/commands/window/status.sh"
            window_status "${args[@]}"
            ;;
        close|c)
            # shellcheck source=close.sh
            source "${LIB_DIR}/commands/window/close.sh"
            window_close "${args[@]}"
            ;;
        open|o)
            # shellcheck source=open.sh
            source "${LIB_DIR}/commands/window/open.sh"
            window_open "${args[@]}"
            ;;
        move|mv)
            # shellcheck source=move.sh
            source "${LIB_DIR}/commands/window/move.sh"
            window_move "${args[@]}"
            ;;
        focus|f)
            # shellcheck source=focus.sh
            source "${LIB_DIR}/commands/window/focus.sh"
            window_focus "${args[@]}"
            ;;
        minimize|min)
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
Usage: kdoitall window (win) <subcommand> [options]

Window Subcommands:
  list (ls) [workspace]                     List tracked windows
  status (st) <window-name>                 Show window details
  close (c) <window-name>                   Close a specific window
  open (o) <window-name>                    Re-open a previously closed window
  move (mv) <window-name> [move-options]    Move/reposition a window
  focus (f) <window-name>                   Bring window to front
  minimize (min) <window-name>              Minimize window

Move Command:
  Positional:  move <name> <desktop> [screen] [position]
  Flags:       move <name> --desktop <n> --screen <ref> --position <pos>
  Short flags: -d, -s, -p
  Positions:   Fullscreen (fs), Right Half (rh), Left Half (lh),
               Top Half (th), Bottom Half (bh), Top Left (tl),
               Top Right (tr), Bottom Left (bl), Bottom Right (br),
               Left Third (lt), Middle Third (mt), Right Third (rt)

Examples:
  kdoitall window list
  kdoitall win ls dev-env
  kdoitall window status dev-env-firefox-1
  kdoitall win st dev-env-firefox-1
  kdoitall window close dev-env-firefox-1
  kdoitall win c dev-env-firefox-1
  kdoitall window open dev-env-firefox-1
  kdoitall win mv dev-env-firefox-1 2
  kdoitall window move dev-env-firefox-1 2 1 fs
  kdoitall win mv dev-env-firefox-1 -d 2 -s 1 -p tl
  kdoitall window move dev-env-firefox-1 --position "Right Half"
  kdoitall win f dev-env-firefox-1
  kdoitall win min dev-env-firefox-1

EOF
}
