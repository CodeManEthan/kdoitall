#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_and_set_guard "_KDOITALL_WORKSPACE_COMMAND_LOADED" || return 0

workspace_command() {
    local function_name="workspace_command"
    local subcommand=""
    local -a args=()
    
    # Parse arguments, filtering out global flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug|--verbose)
                # Skip global flags - already handled by main script
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
        echo "Error: Workspace subcommand required" >&2
        workspace_show_help
        return 1
    fi
    
    # Dispatch to appropriate handler
    case "$subcommand" in
        create)
            # shellcheck source=create.sh
            source "${LIB_DIR}/commands/workspace/create.sh"
            workspace_create "${args[@]}"
            ;;
        list)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/workspace/list.sh"
            workspace_list "${args[@]}"
            ;;
        open)
            # shellcheck source=open.sh
            source "${LIB_DIR}/commands/workspace/open.sh"
            workspace_open "${args[@]}"
            ;;
        close)
            # shellcheck source=close.sh
            source "${LIB_DIR}/commands/workspace/close.sh"
            workspace_close "${args[@]}"
            ;;
        delete)
            # shellcheck source=delete.sh
            source "${LIB_DIR}/commands/workspace/delete.sh"
            workspace_delete "${args[@]}"
            ;;
        *)
            echo "Error: Unknown workspace subcommand: $subcommand" >&2
            workspace_show_help
            return 1
            ;;
    esac
}

workspace_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall workspace <subcommand> [options]

Workspace Subcommands:
  create <name>     Create a new workspace interactively
  list              List all defined workspaces
  open <name>       Open a workspace
  close <name>      Close a workspace
  delete <name>     Delete a workspace

Examples:
  kdoitall workspace create dev-environment
  kdoitall workspace list
  kdoitall workspace open dev-environment
  kdoitall workspace close dev-environment
  kdoitall workspace delete old-workspace

For more information, see the workspace creation system documentation.
EOF
}
