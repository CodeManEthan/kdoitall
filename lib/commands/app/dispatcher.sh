#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_COMMAND_LOADED" || return 0

app_command() {
    local function_name="app_command"
    local subcommand=""
    local -a args=()
    
    # Parse arguments, filtering out global flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug|--verbose)
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
    
    # Dispatch to appropriate handler
    case "$subcommand" in
        scan)
            # shellcheck source=scan.sh
            source "${LIB_DIR}/commands/app/scan.sh"
            app_scan "${args[@]}"
            ;;
        list)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/app/list.sh"
            app_list "${args[@]}"
            ;;
        info)
            # shellcheck source=info.sh
            source "${LIB_DIR}/commands/app/info.sh"
            app_info "${args[@]}"
            ;;
        validate)
            # shellcheck source=validate.sh
            source "${LIB_DIR}/commands/app/validate.sh"
            app_validate "${args[@]}"
            ;;
        options)
            # shellcheck source=options.sh
            source "${LIB_DIR}/commands/app/options.sh"
            app_options "${args[@]}"
            ;;
        safe-mode)
            # shellcheck source=safe-mode.sh
            source "${LIB_DIR}/commands/app/safe-mode.sh"
            app_safe_mode "${args[@]}"
            ;;
        *)
            echo "Error: Unknown app subcommand: $subcommand" >&2
            app_show_help
            return 1
            ;;
    esac
}

app_show_help() {
    cat << 'EOF'
Usage: kdoitall app <subcommand> [options]

App Subcommands:
  scan              Scan system for available applications and populate registry
  list [filter]     List applications from registry
                    Filters: all (default), terminal, desktop, both
  info <app_id>     Show detailed information about a specific application
  validate          Validate all application definition files
  options <app_id>  Show launch options for an application
  safe-mode              Interactive safe-mode validation menu
  safe-mode skip <id>    Mark app as validated without running safe-mode
  safe-mode reset <id>   Clear safe-mode data (will prompt again)

Examples:
  kdoitall app scan
  kdoitall app list
  kdoitall app list terminal
  kdoitall app info firefox
  kdoitall app validate
  kdoitall app options konsole

For more information, see the application registry documentation.
EOF
}
