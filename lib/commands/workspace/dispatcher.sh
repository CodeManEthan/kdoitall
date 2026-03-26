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
        create|new)
            # Check for --from-file flag
            local from_file=""
            local replace_flag="false"
            local create_args=()
            local i=0
            while [[ $i -lt ${#args[@]} ]]; do
                case "${args[$i]}" in
                    --from-file)
                        ((i++)) || true
                        from_file="${args[$i]:-}"
                        ;;
                    --replace)
                        replace_flag="true"
                        ;;
                    *)
                        create_args+=("${args[$i]}")
                        ;;
                esac
                ((i++)) || true
            done

            if [[ -n "$from_file" ]]; then
                # shellcheck source=import.sh
                source "${LIB_DIR}/commands/workspace/import.sh"
                workspace_create_from_file "${create_args[0]:-}" "$from_file" "$replace_flag"
            else
                # shellcheck source=create.sh
                source "${LIB_DIR}/commands/workspace/create.sh"
                workspace_create "${create_args[@]}"
            fi
            ;;
        list|ls)
            # shellcheck source=list.sh
            source "${LIB_DIR}/commands/workspace/list.sh"
            workspace_list "${args[@]}"
            ;;
        info|i)
            # shellcheck source=info.sh
            source "${LIB_DIR}/commands/workspace/info.sh"
            workspace_info "${args[@]}"
            ;;
        edit|e)
            # Detect non-interactive flags
            local has_edit_flags=false
            local edit_description=""
            local has_description_flag=false
            local edit_focus_window=""
            local has_focus_window_flag=false
            local edit_positional=""
            local j=0
            while [[ $j -lt ${#args[@]} ]]; do
                case "${args[$j]}" in
                    --description)
                        has_edit_flags=true
                        has_description_flag=true
                        ((j++)) || true
                        edit_description="${args[$j]:-}"
                        ;;
                    --focus-window)
                        has_edit_flags=true
                        has_focus_window_flag=true
                        ((j++)) || true
                        edit_focus_window="${args[$j]:-}"
                        ;;
                    *)
                        edit_positional="${args[$j]}"
                        ;;
                esac
                ((j++)) || true
            done

            # shellcheck source=edit.sh
            source "${LIB_DIR}/commands/workspace/edit.sh"
            if [[ "$has_edit_flags" == true ]]; then
                workspace_edit_noninteractive "$edit_positional" "$edit_description" \
                    "$has_description_flag" "$has_focus_window_flag" "$edit_focus_window"
            else
                workspace_edit "${args[@]}"
            fi
            ;;
        add-window|aw)
            # shellcheck source=add-window.sh
            source "${LIB_DIR}/commands/workspace/add-window.sh"
            workspace_add_window "${args[@]}"
            ;;
        edit-window|ew)
            # shellcheck source=edit-window.sh
            source "${LIB_DIR}/commands/workspace/edit-window.sh"
            workspace_edit_window "${args[@]}"
            ;;
        remove-window|rw)
            # shellcheck source=remove-window.sh
            source "${LIB_DIR}/commands/workspace/remove-window.sh"
            workspace_remove_window "${args[@]}"
            ;;
        open|o)
            # shellcheck source=open.sh
            source "${LIB_DIR}/commands/workspace/open.sh"
            workspace_open "${args[@]}"
            ;;
        close|c)
            # shellcheck source=close.sh
            source "${LIB_DIR}/commands/workspace/close.sh"
            workspace_close "${args[@]}"
            ;;
        focus|f)
            # shellcheck source=focus.sh
            source "${LIB_DIR}/commands/workspace/focus.sh"
            workspace_focus "${args[@]}"
            ;;
        minimize|min)
            # shellcheck source=minimize.sh
            source "${LIB_DIR}/commands/workspace/minimize.sh"
            workspace_minimize "${args[@]}"
            ;;
        delete|rm)
            # shellcheck source=delete.sh
            source "${LIB_DIR}/commands/workspace/delete.sh"
            workspace_delete "${args[@]}"
            ;;
        export|exp)
            # shellcheck source=export.sh
            source "${LIB_DIR}/commands/workspace/export.sh"
            workspace_export "${args[@]}"
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
Usage: kdoitall workspace (ws) <subcommand> [options]

Workspace Subcommands:
  create (new) <n>     Create a new workspace interactively
    --from-file <path>   Create workspace from JSON config file
    --replace            Replace existing workspace (with --from-file)
  export (exp) <n>     Export workspace definition to JSON (stdout)
  edit (e) <n>         Edit an existing workspace (interactive)
    --description "..."  Set description (non-interactive)
    --focus-window "n"   Set focus window ("" to clear)
  add-window (aw) <n>  Add a window to a workspace
    --name, --app, --desktop, --screen, --position (required)
    --function, --params (optional)
  edit-window (ew) <n> <win>  Edit a window definition
    --name, --desktop, --screen, --position, --function, --params, --display-order
  remove-window (rw) <n> <win>  Remove a window from a workspace
  list (ls) [--details]   List all defined workspaces
  info (i) <n>         Show detailed info for a workspace
  open (o) [--skip] <n>  Open a workspace (--skip bypasses safe mode)
  close (c) <n>        Close a workspace
  focus (f) <n>        Focus an active workspace (raise + activate)
  minimize (min) <n>   Minimize all windows in an active workspace
  delete (rm) <n>      Delete a workspace

Examples:
  kdoitall workspace create dev-environment
  kdoitall ws new dev-environment
  kdoitall workspace create my-env --from-file my-env.json
  kdoitall workspace create my-env --from-file my-env.json --replace
  kdoitall workspace export my-env > my-env.json
  kdoitall workspace edit dev-env --description "My dev setup"
  kdoitall workspace edit dev-env --focus-window dev-firefox
  kdoitall workspace edit dev-env --focus-window ""
  kdoitall ws aw dev-env --name dev-code -a code -d 1 -s 1 -p fs
  kdoitall ws ew dev-env dev-code --desktop 2 --position lh
  kdoitall ws ew dev-env dev-code --name dev-editor
  kdoitall ws rw dev-env dev-code
  kdoitall workspace list
  kdoitall ws ls --details
  kdoitall workspace open dev-environment
  kdoitall ws o dev-environment
  kdoitall workspace close dev-environment
  kdoitall ws c dev-environment
  kdoitall workspace delete old-workspace
  kdoitall ws rm old-workspace

For more information, see the workspace creation system documentation.
EOF
}
