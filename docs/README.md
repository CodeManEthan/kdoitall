# Codebase Impact Maps

**Purpose:** Answer one question — *"I'm changing X — what else in the codebase might break?"*

These docs are maintained by Claude and referenced during feature implementation. They are updated alongside every code change that affects data structures, relationships, or flows.

## How to Use

1. **Before modifying a module:** Open its module doc, review the Function Impact Map, and work through the Change Checklist
2. **Before modifying a cross-module flow:** Open the relevant flow doc and trace the pipeline
3. **For structural changes:** Use the appropriate checklist in `checklists/`

## Module Docs

| Module | File | Description |
|--------|------|-------------|
| [Database](modules/database.md) | `modules/database.md` | SQLite schema, DB server lifecycle, query patterns, window tracking tables |
| [Window Management](modules/window-management.md) | `modules/window-management.md` | Window detection, positioning, movement, desktop/screen operations |
| [App Registry](modules/app-registry.md) | `modules/app-registry.md` | App scanning, registration, launch options, app definition files |
| [Workspace](modules/workspace.md) | `modules/workspace.md` | Workspace CRUD, script generation, window definitions, open/close commands |
| [Core Engine](modules/core-engine.md) | `modules/core-engine.md` | Launch pipeline (execute_launch_window), close pipeline, auto-detect |
| [Screen & Desktop](modules/screen-desktop.md) | `modules/screen-desktop.md` | kscreen-doctor integration, screen detection, desktop switching, aliases |
| [Safe Mode](modules/safe-mode.md) | `modules/safe-mode.md` | Missing metadata validation, interactive prompts, auto-learning |

## Flow Docs

| Flow | File | Description |
|------|------|-------------|
| [Window Launch Pipeline](flows/window-launch-pipeline.md) | `flows/window-launch-pipeline.md` | 7-phase execute_launch_window process |
| [Workspace Open/Close](flows/workspace-open-close.md) | `flows/workspace-open-close.md` | Full workspace open/close lifecycle with script generation |
| [App Discovery](flows/app-discovery.md) | `flows/app-discovery.md` | .desktop file scanning, metadata extraction, registry population |
| [Window Detection](flows/window-detection.md) | `flows/window-detection.md` | Process-of-elimination detection, splash window handling, stability checks |

## Checklists

| Checklist | File | Description |
|-----------|------|-------------|
| [Adding an Application](checklists/adding-an-application.md) | `checklists/adding-an-application.md` | Adding support for a new application (definition files, functions, metadata) |
| [Adding a Command](checklists/adding-a-command.md) | `checklists/adding-a-command.md` | Adding a new CLI command or subcommand (dispatcher, handler, help) |
| [Modifying Database Schema](checklists/modifying-database-schema.md) | `checklists/modifying-database-schema.md` | Adding/modifying database tables or columns |

## Function Tier System

Each function in a module doc is classified by blast radius:

- **Tier 1 — Wide blast radius:** Full detail — every caller, every database table touched, every constant used. Functions called from many modules.
- **Tier 2 — Moderate blast radius:** Service + command level tracking. Functions with several callers within the module boundary.
- **Tier 3 — Narrow blast radius:** Brief note on purpose and location. Internal helpers called within the module only.
