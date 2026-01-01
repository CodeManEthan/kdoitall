#!/bin/bash

# ============================================================================
# Help Command
# ============================================================================
# Displays usage information and available commands

check_and_set_guard "_KDOITALL_HELP_LOADED" || return 0

# ============================================================================
# show_help()
# Display usage information and command list
# ============================================================================
# Parameters: None
# Returns: 0
# ============================================================================
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

EXAMPLES:
    # Create a new workspace
    kdoitall workspace create my-dev-workspace

    # List all workspaces
    kdoitall workspace list

    # Open a workspace
    kdoitall workspace open my-dev-workspace

    # Close a workspace
    kdoitall workspace close my-dev-workspace

For more information, visit: https://github.com/yourusername/kdoitall

EOF
}
