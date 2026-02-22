#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_HELP_LOADED" || return 0

show_help() {
    cat << 'EOF'
kdoitall - KDE Desktop Automation Tool

USAGE:
    kdoitall [OPTIONS] <COMMAND> [ARGS...]

OPTIONS:
    --help, -h       Show this help message
    --version, -v    Show version information
    --info           Show key milestones during execution
    --verbose        Enable verbose output

STATUS:
    status                Show current state of active workspaces and windows
    update                Update kdoitall (git pull + rebuild app registry)

WORKSPACE COMMANDS:
    workspace create <name>   Create new workspace interactively
    workspace list            List all defined workspaces
    workspace open <name>     Open a workspace
    workspace close <name>    Close a workspace
    workspace focus <name>    Focus an active workspace
    workspace minimize <name> Minimize an active workspace
    workspace delete <name>   Delete a workspace

APPLICATION COMMANDS:
    app scan                  Scan system for available applications
    app list [filter]         List applications (all, terminal, desktop, both)
    app info <app_id>         Show detailed information about an application
    app validate              Validate all application definition files
    app options <app_id>      Show launch options for an application
    app safe-mode                 Interactive safe-mode validation menu
    app safe-mode skip <app_id>   Mark app as validated (skip safe-mode)
    app safe-mode reset <app_id>  Clear safe-mode data for an app

SCREEN COMMANDS:
    screen list                        List detected screens with aliases
    screen alias <alias> <target>      Set a screen alias
    screen alias remove <alias>        Remove a screen alias

WINDOW COMMANDS:
    window list [workspace]                     List tracked windows
    window status <window-name>                 Show window details
    window close <window-name>                  Close a specific window
    window open <window-name>                   Re-open a previously closed window
    window move <window-name> <screen> <pos>    Move/reposition a window
    window focus <window-name>                  Bring window to front
    window minimize <window-name>               Minimize window

CONFIGURATION:
    Project defaults:     <install-dir>/config
    User overrides:       ~/.config/kdoitall/config

    Settings:
      SAFE_MODE_PROMPTING   "enabled" or "disabled" — controls whether workspace
                            open prompts for unvalidated apps (default: enabled)

EXAMPLES:
    # Create a new workspace
    kdoitall workspace create my-dev-workspace

    # List all workspaces
    kdoitall workspace list

    # Open a workspace
    kdoitall workspace open my-dev-workspace

    # Close a workspace
    kdoitall workspace close my-dev-workspace

    # List tracked windows
    kdoitall window list

    # Show window details
    kdoitall window status my-dev-firefox-1

    # Close and re-open a window
    kdoitall window close my-dev-firefox-1
    kdoitall window open my-dev-firefox-1

For more information, visit: https://github.com/CodeManEthan/kdoitall

EOF
}
