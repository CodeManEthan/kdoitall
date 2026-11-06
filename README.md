# kdoitall

**KDE Desktop Automation Tool**

![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)![Version: v0.2.1](https://img.shields.io/badge/Version-v0.2.1-green.svg)

![kdoitall workspace open demo: one command places five apps across two screens](docs/media/kdoitall-demo.gif)

*`kdoitall workspace open demo` places five apps on their screens and tiles across a two-monitor desktop. The placement is shown at 4x speed.*

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
```

### Global Options
```
--help, -h       Show help message
--version, -v    Show version
--info           Show key milestones during execution
--verbose        Enable verbose output
```

### Status & Update
```
status (st)      Show current state of active workspaces and windows
update           Update kdoitall (git pull + rebuild app registry)
```

### Quick Action (quick | q)

```
quick            Interactive window picker for ad-hoc actions
```

### Workspace Commands (workspace | ws)

#### Main commands

```
create (new) <name>                   Create a new workspace interactively
list (ls) [--details]                 List all defined workspaces
info (i) <name>                       Show detailed info for a workspace
edit (e) <name>                       Edit an existing workspace (interactive)
open (o) [--skip] <name>              Open a workspace (--skip bypasses safe mode)
close (c) <name>                      Close a workspace
focus (f) <name>                      Focus an active workspace (raise + activate)
minimize (min) <name>                 Minimize all windows in an active workspace
delete (rm) <name>                    Delete a workspace
```

#### Non-interactive / scripted commands

```
create (new) <name>                    Create a workspace from a JSON config file
  --from-file <path>                     Path to JSON config (required)
  --replace                              Replace existing workspace
export (exp) <name>                    Export workspace definition to JSON (stdout)
edit (e) <name>                        Edit an existing workspace non-interactively
  --description "..."                    Set description
  --focus-window "name"                  Set focus window ("" to clear)
add-window (aw) <name>                 Add a window to a workspace
  --name, --app, --desktop, --screen, --position (required)
  --function, --params (optional)
edit-window (ew) <name> <window>       Edit a window definition
  --name, --desktop, --screen, --position, --function, --params, --display-order
remove-window (rw) <name> <window>     Remove a window from a workspace
```

### Application Commands (app)
```
scan                                  Scan system for available applications
list (ls) [filter]                    List applications (all, terminal, desktop, both)
info (i) <app_id|name>               Show detailed information about an application
validate                              Validate all application definition files
options (opts) <app_id>               Show launch options for an application
name (n) <app_id> <name>             Set a custom app name
name (n) reset <app_id>              Clear manual override (reverts to auto on next scan)
set-terminal (st) <app_id> [flag]    Mark app as terminal emulator (default exec flag: -e)
unset-terminal (ust) <app_id>        Remove terminal emulator classification
safe-mode (sm)                        Interactive safe-mode validation menu
safe-mode (sm) skip <app_id>         Mark app as validated (skip safe-mode)
safe-mode (sm) reset <app_id>        Clear safe-mode data for an app
```

### Screen Commands (screen | scr)
```
list (ls)                             List detected screens with aliases
alias <alias> <target>                Set a screen alias (target: number or name)
alias remove <alias>                  Remove a screen alias
```
### Window Commands (window | win)

```
list (ls) [workspace]                 List tracked windows
status (st) <window-name>             Show window details
close (c) <window-name>               Close a specific window
open (o) <window-name>                Re-open a previously closed window
focus (f) <window-name>               Bring window to front
minimize (min) <window-name>          Minimize window
```

#### move (mv) — reposition a window

```
move (mv) <window-name> [options]

Positional mode (order: desktop, screen, position):
  move <name> <desktop>
  move <name> <desktop> <screen>
  move <name> <desktop> <screen> <position>

Flag mode (any combination, any order):
  --desktop, -d <n>      Target virtual desktop
  --screen, -s <ref>     Target screen (number or alias)
  --position, -p <pos>   Window position preset
  --focus, -f            Focus the window after moving

Unspecified properties are preserved.
```

## Project Status

kdoitall is in a stable state with a broad set of features for workspace automation and window management. Further testing is ongoing to improve reliability and handle remaining edge cases.

Current gaps:

- Limited metadata coverage in the app-registry database — most applications still require safe-mode to gather launch properties
- Application definitions only exist for VS Code and Firefox — other apps use generic launch behavior

## Documentation
In-depth architecture details, function maps, and change checklists live in the [`docs/`](docs/README.md) directory:

- [`docs/modules/`](docs/modules) — per-module references (database, window management, app registry, workspace, core engine, screen/desktop, safe mode)
- [`docs/flows/`](docs/flows) — end-to-end workflow guides (window launch pipeline, workspace open/close, app discovery, window detection)
- [`docs/checklists/`](docs/checklists) — step-by-step procedures for structural changes (adding an application, adding a command, modifying the database schema)

Database schema changes are applied automatically on each startup via forward-only migrations in [`database/migrations/`](database/migrations). See [`docs/modules/database.md`](docs/modules/database.md) for details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture details, coding standards, and how to add application support.

## License
```
kdoitall - KDE Desktop Automation Tool
Copyright (C) 2025 Ethan Plunk

Licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later).
See the LICENSE file for the full license text.
```