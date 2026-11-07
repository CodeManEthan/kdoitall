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
    --help, -h                   Show this help message
    --version, -v                Show version information
    --info                       Show key milestones during execution
    --verbose                    Enable verbose output
    --restart-snapshot-daemon    Stop and respawn the KWin snapshot daemon

STATUS:
    status (st)           Show current state of active workspaces and windows
    update                Update kdoitall (git pull + rebuild app registry)

QUICK ACTION (quick | q):
    quick                   Interactive window picker for ad-hoc actions

WORKSPACE COMMANDS (workspace | ws):
    workspace create (new) <name>       Create new workspace interactively
    workspace create (new) <name> --from-file <json> [--replace]
                                        Create a workspace from a JSON file
                                        (--replace overwrites one of that name)
    workspace export (exp) <name>       Print a workspace as JSON (stdout)
    workspace edit (e) <n>              Edit an existing workspace
    workspace edit (e) <n> --description "..." --focus-window <w>
                                        Set either one without prompts
                                        (--focus-window "" clears it)
    workspace add-window (aw) <n>       Add a window to a workspace
    workspace edit-window (ew) <n> <w>  Edit a window definition
    workspace remove-window (rw) <n> <w> Remove a window from a workspace
    workspace list (ls) [--details]     List all defined workspaces
    workspace info (i) <n>              Show detailed info for a workspace
    workspace open (o) [--skip] <name>  Open a workspace (--skip bypasses safe mode)
    workspace close (c) <name>          Close a workspace
    workspace focus (f) <name>          Focus an active workspace
    workspace minimize (min) <name>     Minimize an active workspace
    workspace delete (rm) <name>        Delete a workspace

APPLICATION COMMANDS (app):
    app scan                  Scan system for available applications
    app list (ls) [filter]    List applications (all, terminal, desktop)
    app info (i) <app_id|name> Show detailed information about an application
    app validate              Validate all application definition files
    app options (opts) <id>   Show launch options for an application
    app name (n) <id> <name>       Set a custom app name
    app name (n) reset <id>        Clear the custom name (the next scan sets it)
    app set-terminal (st) <id> [flag]
                                   Mark app as a terminal emulator
                                   (exec flag defaults to -e)
    app unset-terminal (ust) <id>  Remove the terminal emulator mark
    app safe-mode (sm)             Interactive safe-mode validation menu
    app safe-mode (sm) skip <id>   Mark app as validated (skip safe-mode)
    app safe-mode (sm) reset <id>  Clear safe-mode data for an app

SCREEN COMMANDS (screen | scr):
    screen list (ls)                       List detected screens with aliases
    screen alias <alias> <target>          Set a screen alias
    screen alias remove <alias>            Remove a screen alias

WINDOW COMMANDS (window | win):
    window list (ls) [workspace]                    List tracked windows
    window status (st) <window-name>                Show window details
    window close (c) <window-name>                  Close a specific window
    window open (o) <window-name>                   Re-open a previously closed window
    window move (mv) <window-name> <desktop> [screen] [position]
                                                    Move/reposition a window
                                                    (or -d, -s, -p flags)
    window focus (f) <window-name>                  Bring window to front
    window minimize (min) <window-name>             Minimize window

CONFIGURATION:
    Project defaults:     <install-dir>/config
    User overrides:       ~/.config/kdoitall/config
                          ($XDG_CONFIG_HOME/kdoitall/config if set)

    Settings, any of which the user file can set (default in brackets):
      SAFE_MODE_PROMPTING     "enabled" or "disabled": whether workspace open
                              offers safe mode for unprofiled apps ["enabled"]
      SAFE_MODE_STRICTNESS    "relaxed" (unknown window class) or "strict" (also
                              unknown launch mode or splash) ["relaxed"]
      LOG_TO_FILE             "enabled" writes a verbose log of every run to
                              LOG_DIR ["disabled"]
      LOG_DIR                 Where log files go [~/.local/state/kdoitall/logs,
                              or $XDG_STATE_HOME/kdoitall/logs if set]
      CLOSE_WAIT_TIMEOUT      Seconds workspace close waits for a window before
                              skipping it [60]
      EXTRA_POSITIONS         Bash array of extra position names to turn on,
                              e.g. ("Left Two-Thirds") [not set]
      DESKTOP_FILE_LOCATIONS  Bash array of directories app scan reads .desktop
                              files from. Yours replaces the whole list.
                              [/usr/share/applications
                               /usr/local/share/applications
                               ~/.local/share/applications
                               /var/lib/flatpak/exports/share/applications
                               ~/.local/share/flatpak/exports/share/applications
                               /var/lib/snapd/desktop/applications]

EXAMPLES:
    # Create a new workspace
    kdoitall workspace create my-dev-workspace

    # List all workspaces
    kdoitall workspace list

    # Open a workspace
    kdoitall workspace open my-dev-workspace

    # Close a workspace
    kdoitall workspace close my-dev-workspace

    # Save a workspace to a file, then recreate it from that file
    kdoitall workspace export my-dev-workspace > my-dev-workspace.json
    kdoitall workspace create my-dev-workspace --from-file my-dev-workspace.json --replace

    # List tracked windows
    kdoitall window list

    # Show window details
    kdoitall window status my-dev-firefox-1

    # Move a window to desktop 2, screen 1, left half
    kdoitall window move my-dev-firefox-1 2 1 lh

    # Close and re-open a window
    kdoitall window close my-dev-firefox-1
    kdoitall window open my-dev-firefox-1

For more information, visit: https://github.com/CodeManEthan/kdoitall

EOF
}
