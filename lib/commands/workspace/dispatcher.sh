#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_COMMAND_LOADED" || return 0

workspace_command() {
    local function_name="workspace_command"
    local subcommand=""
    local -a args=()
    
    # Parse arguments, filtering out global flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|--info)
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
        info)
            # shellcheck source=info.sh
            source "${LIB_DIR}/commands/workspace/info.sh"
            workspace_info "${args[@]}"
            ;;
        edit)
            # shellcheck source=edit.sh
            source "${LIB_DIR}/commands/workspace/edit.sh"
            workspace_edit "${args[@]}"
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
        focus)
            # shellcheck source=focus.sh
            source "${LIB_DIR}/commands/workspace/focus.sh"
            workspace_focus "${args[@]}"
            ;;
        minimize)
            # shellcheck source=minimize.sh
            source "${LIB_DIR}/commands/workspace/minimize.sh"
            workspace_minimize "${args[@]}"
            ;;
        delete)
            # shellcheck source=delete.sh
            source "${LIB_DIR}/commands/workspace/delete.sh"
            workspace_delete "${args[@]}"
            ;;
        edit)
            # shellcheck source=edit.sh
            source "${LIB_DIR}/commands/workspace/edit.sh"
            workspace_edit "${args[@]}"
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
  create <n>        Create a new workspace interactively
  edit <n>          Edit an existing workspace
  list [--details]     List all defined workspaces
  info <n>          Show detailed info for a workspace
  open <n>          Open a workspace
  close <n>         Close a workspace
  focus <n>         Focus an active workspace (raise + activate)
  minimize <n>      Minimize all windows in an active workspace
  delete <n>        Delete a workspace

Examples:
  kdoitall workspace create dev-environment
  kdoitall workspace edit dev-environment
  kdoitall workspace list
  kdoitall workspace list --details
  kdoitall workspace info dev-environment
  kdoitall workspace open dev-environment
  kdoitall workspace close dev-environment
  kdoitall workspace delete old-workspace

For more information, see the workspace creation system documentation.
EOF
}
