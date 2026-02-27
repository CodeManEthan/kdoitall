# kdoitall

**KDE Desktop Automation Tool**

![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)
![Version: v0.2.0](https://img.shields.io/badge/Version-v0.2.0-green.svg)

## About

kdoitall automates workspace management on KDE Plasma desktops. Define a workspace as a collection of applications, assign each one a screen, virtual desktop, and window position, then open and close the entire workspace with a single command. Individual windows can also be manipulated on-the-fly using `kdoitall quick` and the window commands, without needing to define a workspace.

It supports multi-screen and multi-desktop setups on both Wayland and X11, uses SQLite for state tracking, and detects installed applications automatically from `.desktop` files.

## Key Features

- **Workspace management** — Create, open, close, and delete named workspaces with interactive configuration
- **Multi-screen and multi-desktop** — Place windows on specific screens and virtual desktops
- **28 window position presets** — 12 defaults (fullscreen, halves, thirds, and quadrants) plus 16 optional positions (two-thirds, 60/40, center, and quarter splits) enabled via `EXTRA_POSITIONS` config
- **Application registry** — Auto-detects installed applications from `.desktop` files via `app scan`
- **Custom launch functions** — Per-application launch behavior through the app-definitions system
- **Database-driven state** — SQLite-backed tracking of workspaces, applications, and window state

## Requirements

- **Desktop Environment:** KDE Plasma 5.x or 6.x
- **Display Server:** Wayland (recommended) or X11
- **Shell:** Bash 4.0+

### Dependencies

| Command          | Purpose                        |
|------------------|--------------------------------|
| `kdotool`        | KDE window management          |
| `kscreen-doctor` | Screen/display detection       |
| `sqlite3`        | Database operations            |
| `jq`             | JSON parsing                   |
| `gtk-launch`     | Application launching          |

> **Note:** `kdotool` is not available in standard package repos for most distributions. The install script can automatically download and install it for you, or you can install it manually from https://github.com/jinliu/kdotool

## Installation
```bash
git clone https://github.com/CodeManEthan/kdoitall.git
cd kdoitall
./scripts/install.sh
```

To uninstall:
```bash
./scripts/uninstall.sh
```

## Quick Start
```bash
# Scan for installed applications
kdoitall app scan

# Create a new workspace (interactive)
kdoitall workspace create my-workspace

# Open the workspace
kdoitall workspace open my-workspace

# Close the workspace
kdoitall workspace close my-workspace
```

## Usage
```
kdoitall [OPTIONS] <COMMAND> [ARGS...]

OPTIONS:
    --help, -h       Show help message
    --version, -v    Show version
    --info           Show key milestones during execution
    --verbose        Enable verbose output

STATUS:
    status (st)           Show current state of active workspaces and windows
    update                Update kdoitall (git pull + rebuild app registry)

QUICK ACTION (quick | q):
    quick                   Interactive window picker for ad-hoc actions

WORKSPACE COMMANDS (workspace | ws):
    workspace create (new) <n>   Create new workspace interactively
    workspace edit (e) <n>       Edit an existing workspace
    workspace list (ls)             List all defined workspaces
    workspace info (i) <n>       Show detailed info for a workspace
    workspace open (o) <n>       Open a workspace
    workspace close (c) <n>      Close a workspace
    workspace focus (f) <n>      Focus an active workspace
    workspace minimize (min) <n> Minimize an active workspace
    workspace delete (rm) <n>    Delete a workspace

APPLICATION COMMANDS (app):
    app scan                  Scan system for available applications
    app list (ls) [filter]    List applications (all, terminal, desktop, both)
    app info (i) <app_id>     Show detailed information about an application
    app validate              Validate all application definition files
    app options (opts) <id>   Show launch options for an application
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
    window move (mv) <window-name> <screen> <pos>   Move/reposition a window (Accepts --focus|-f)
    window focus (f) <window-name>                  Bring window to front
    window minimize (min) <window-name>             Minimize window
```

## Project Status

kdoitall is in a stable state with a broad set of features for workspace automation and window management. Further testing is ongoing to improve reliability and handle remaining edge cases.

Current gaps:

- Limited metadata coverage in the app-registry database — most applications still require safe-mode to gather launch properties
- Application definitions only exist for VS Code and Firefox — other apps use generic launch behavior

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture details, coding standards, and how to add application support.

## License
```
kdoitall - KDE Desktop Automation Tool
Copyright (C) 2025 Ethan Plunk

Licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later).
See the LICENSE file for the full license text.
```