#!/bin/bash

# ============================================================================
# Workspace Command Dispatcher
# ============================================================================
# Main entry point for workspace subcommands
# Routes to appropriate workspace-*.sh command files

check_and_set_guard "_KDOITALL_WORKSPACE_COMMAND_LOADED" || return 0

# ----------------------------------------------------------------------------
# workspace_command()
# Dispatch workspace subcommands to appropriate handlers
# Parameters:
#   $1 - subcommand (create, list, open, close, delete)
#   $@ - additional arguments passed to subcommand
# ----------------------------------------------------------------------------
workspace_command() {
    local subcommand="$1"
    shift
    
    # Validate subcommand provided
    if [[ -z "$subcommand" ]]; then
        echo "Error: Workspace subcommand required"
        workspace_show_help
        return 1
    fi
    
    # Dispatch to appropriate handler
    case "$subcommand" in
        create)
            # shellcheck source=workspace-create.sh
            source "${LIB_DIR}/commands/workspace-create.sh"
            workspace_create "$@"
            ;;
        list)
            # shellcheck source=workspace-list.sh
            source "${LIB_DIR}/commands/workspace-list.sh"
            workspace_list "$@"
            ;;
        open)
            # shellcheck source=workspace-open.sh
            source "${LIB_DIR}/commands/workspace-open.sh"
            workspace_open "$@"
            ;;
        close)
            # shellcheck source=workspace-close.sh
            source "${LIB_DIR}/commands/workspace-close.sh"
            workspace_close "$@"
            ;;
        delete)
            # shellcheck source=workspace-delete.sh
            source "${LIB_DIR}/commands/workspace-delete.sh"
            workspace_delete "$@"
            ;;
        *)
            echo "Error: Unknown workspace subcommand: $subcommand"
            workspace_show_help
            return 1
            ;;
    esac
}

# ----------------------------------------------------------------------------
# workspace_show_help()
# Display usage information for workspace commands
# ----------------------------------------------------------------------------
workspace_show_help() {
    cat << 'EOF'
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
