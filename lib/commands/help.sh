#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_and_set_guard "_KDOITALL_HELP_LOADED" || return 0

show_help() {
    cat << 'EOF'
kdoitall - KDE Desktop Automation Tool

USAGE:
    kdoitall [OPTIONS] <COMMAND> [ARGS...]

OPTIONS:
    --help, -h       Show this help message
    --version, -v    Show version information
    --debug          Enable debug output
    --verbose        Enable verbose output

WORKSPACE COMMANDS:
    workspace create <name>   Create new workspace interactively
    workspace list            List all defined workspaces
    workspace open <name>     Open a workspace
    workspace close <name>    Close a workspace
    workspace delete <name>   Delete a workspace

APPLICATION COMMANDS:
    app scan                  Scan system for available applications
    app list [filter]         List applications (all, terminal, desktop, both)
    app info <app_id>         Show detailed information about an application
    app validate              Validate all application definition files
    app options <app_id>      Show launch options for an application

EXAMPLES:
    # Create a new workspace
    kdoitall workspace create my-dev-workspace

    # List all workspaces
    kdoitall workspace list

    # Open a workspace
    kdoitall workspace open my-dev-workspace

    # Close a workspace
    kdoitall workspace close my-dev-workspace

For more information, visit: https://github.com/j-ethan-plunk/kdoitall

EOF
}
