# Planning Instructions

When creating an implementation plan, always list the relevant reference docs
at the top of the plan before any implementation details. Read these docs
before writing any code.

## Documentation Directory: `docs/`

### Module docs (`docs/modules/`)
Core system modules — function maps, dependencies, database tables, change checklists.

- `database.md` — SQLite schema, DB server lifecycle, query patterns, window tracking tables
- `window-management.md` — Window detection, positioning, movement, desktop/screen operations
- `app-registry.md` — App scanning, registration, launch options, app definition files
- `workspace.md` — Workspace CRUD, script generation, window definitions, open/close commands
- `core-engine.md` — Launch pipeline (execute_launch_window), close pipeline, auto-detect
- `screen-desktop.md` — kscreen-doctor integration, screen detection, desktop switching, aliases
- `safe-mode.md` — Missing metadata validation, interactive prompts, auto-learning

### Flow docs (`docs/flows/`)
End-to-end workflows spanning multiple modules.

- `window-launch-pipeline.md` — 7-phase execute_launch_window process
- `workspace-open-close.md` — Full workspace open/close lifecycle with script generation
- `app-discovery.md` — .desktop file scanning, metadata extraction, registry population
- `window-detection.md` — Process-of-elimination detection, splash window handling, stability checks

### Checklists (`docs/checklists/`)
Step-by-step procedures for common structural changes.

- `adding-an-application.md` — Adding support for a new application (definition files, functions, metadata)
- `adding-a-command.md` — Adding a new CLI command or subcommand (dispatcher, handler, help)
- `modifying-database-schema.md` — Adding/modifying database tables or columns

## How to use

1. Before planning, identify which modules, flows, and checklists are affected.
2. List those doc paths at the top of the plan under a "Reference Docs" heading.
3. Read each listed doc before writing implementation steps.
4. If the plan touches a module, always read its `docs/modules/` doc.
5. If the plan involves a multi-step workflow, read the relevant `docs/flows/` doc.
6. If the plan involves structural changes (new apps, new commands, schema changes), read the relevant `docs/checklists/` doc.

---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. For in-depth architecture details, function maps, and change checklists, see the [`docs/`](docs/README.md) directory.

## Project Overview

kdoitall is a KDE Desktop Automation Tool written in Bash that manages workspaces by launching applications, positioning windows across multiple desktops and screens, and tracking window state in an SQLite database.

**Key concepts:**
- **Workspaces** are named collections of windows. Users create them interactively or from JSON config files. Opening a workspace launches all its applications and positions them.
- **Applications** are discovered by scanning `.desktop` files. Apps with custom terminal launch functions live in `lib/app-definitions/apps/<app_id>/` (a `metadata.json` + `functions.sh` pair).
- **Window detection** uses process-of-elimination against `kdotool` snapshots — there is no direct "launch app, get window ID" API on KDE/Wayland.
- **Safe mode** interactively validates unknown apps on first use (detects window class, splash behavior, launch mode, PID support, title patterns) and caches results.

## Architecture

The codebase uses a strict 4-layer dependency system enforced in `bin/kdoitall`:

1. **Layer 1 — Foundation**: `lib/core/error-codes.sh`, `lib/utils/debug.sh`
2. **Layer 2 — Core Utilities**: `lib/core/common.sh`, `lib/utils/positions.sh`, `lib/utils/checks.sh`, `lib/utils/validators.sh`
3. **Layer 3 — Core Services**: `lib/db/helpers.sh`, `lib/core/database.sh`, `lib/core/ydotool.sh`
4. **Layer 4 — Runtime Detection**: `lib/core/screen-detection.sh`

Each layer only depends on layers below it. Source files in the correct order or the system will fail.

SQLite schema (`database/schema.sql`) has 8 tables: `workspace_definitions`, `app_windows`, `tabs`, `applications`, `launch_options`, `launch_parameters`, `screen_aliases`, `window_definitions`. All SQL flows through a Python coproc server; Bash reads results from global arrays (`DB_STATUS`, `DB_RESULT[]`, `DB_ERROR`).

The main binary auto-detaches to background via `nohup` unless `--info`/`--verbose` flags are used or the command is informational (read-only output).

## Common Commands

```bash
# Run automated test suite
./tests/run-tests.sh [--skip 4,5,6]

# Development reset (clears runtime state)
./scripts/dev-reset.sh

# Application management
kdoitall app scan                        # Discover apps from .desktop files
kdoitall app list [all|terminal|desktop]  # List registered apps
kdoitall app info <app_id>               # Show app details
kdoitall app options <app_id>            # Show launch options
kdoitall app validate                    # Validate definition files

# Workspace operations
kdoitall workspace create <name>                    # Interactive creation
kdoitall workspace create <name> --from-file <json> # Create from JSON config
kdoitall workspace open <name>                      # Launch workspace
kdoitall workspace close <name>                     # Close workspace
kdoitall workspace list                             # List workspaces

# Debugging
kdoitall --verbose workspace open <name>  # Full debug trace
kdoitall --info workspace open <name>     # Info-level logging
```

## Shell Coding Standards

- All scripts use `set -euo pipefail`
- Use source guards: `check_and_set_guard "_KDOITALL_MODULE_LOADED" || return 0`
- Pass all function parameters explicitly (no globals except constants)
- Use `local -n` for reference parameters
- Quote all variable expansions
- Use `debug_function_enter`/`debug_function_exit` for tracing
- Parameter validation with `ERR_MISSING_PARAMETER` error codes
- User-facing output goes to fd 3 (via `print_*` functions from `lib/utils/colors.sh`)
- Debug/error output goes to stderr

## Key Dependencies

External tools (checked at startup via `lib/utils/checks.sh`):
- `kdotool` — Window manipulation (KDE Wayland)
- `kscreen-doctor` — Screen detection (KDE)
- `ydotoold` — Keyboard/mouse automation daemon
- `sqlite3` — Database operations (used by Python coproc server)
- `gtk-launch` — Desktop file launching
- `jq` — JSON parsing for app definitions and screen detection
