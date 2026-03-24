# Screen & Desktop Module — Codebase Impact Map

## Overview

This module handles physical screen detection (via kscreen-doctor), virtual desktop management (via kdotool), and window positioning across multi-monitor setups. It populates global associative arrays at startup and provides the coordinate math that all window placement depends on. Screen aliases allow user-friendly names stored in the database.

## Key Files

| File | Role |
|------|------|
| `lib/core/screen-detection.sh` | kscreen-doctor integration, screen/desktop detection |
| `lib/window-management/desktop.sh` | Virtual desktop operations (5 functions) |
| `lib/window-management/screen.sh` | Physical screen positioning (8 functions) |
| `lib/db/screen.sh` | Screen alias persistence (6 functions) |
| `lib/commands/screen/dispatcher.sh` | Screen subcommand routing |
| `lib/commands/screen/list.sh` | Screen listing display |
| `lib/commands/screen/alias.sh` | Screen alias CRUD |

## Function Impact Map

### Tier 1 — High Impact (breaking changes ripple widely)

#### `detect_screens()` — screen-detection.sh
- Calls `kscreen-doctor --json`, parses output with `jq`.
- Populates `SCREEN_INFO[]` associative array with keys: `${output_id}_NAME`, `${output_id}_ENABLED`, `${output_id}_X`, `${output_id}_Y`, `${output_id}_WIDTH`, `${output_id}_HEIGHT`.
- Populates `SCREEN_OUTPUT_IDS[]` and sets `DETECTED_SCREEN_COUNT`.
- Called by `bin/kdoitall` at startup.
- **Impact:** Every downstream screen operation depends on this data. Changes to parsing logic or key naming break all positioning.

#### `detect_desktops()` — screen-detection.sh
- Calls `kdotool get_num_desktops`.
- Sets `DETECTED_DESKTOP_COUNT`.
- Called by `bin/kdoitall` at startup.
- **Impact:** Desktop validation across the entire system depends on this value.

#### `resolve_screen_reference(screen_ref)` — screen-detection.sh
- Three-tier resolution: direct number, then screen name match, then database alias (via `db_get_screen_alias`, recursive).
- **Callers:** `calculate_screen_origin`, `validate_screen_reference`, `move_window_to_screen`, `move_window_to_position` (all in screen.sh), workspace create/edit/import (validation).
- **Impact:** Single point of screen name resolution. Changes to resolution order or alias handling affect all screen-referencing operations.

#### `get_screen_info(output_num, property)` — screen-detection.sh
- Lookup from `SCREEN_INFO[]`. Properties: NAME, UUID, ENABLED, X, Y, WIDTH, HEIGHT.
- **Callers:** `calculate_screen_origin`, `move_window_to_position`, `detect_window_screen`, `detect_window_position` (all in screen.sh).
- **Impact:** All coordinate calculations flow through this function.

### Tier 2 — Medium Impact (used by multiple consumers)

#### `move_window_to_desktop(uuid, desktop)` — desktop.sh
- Validates via `validate_desktop_number`, calls `kdotool set_desktop_for_window`.
- **Callers:** core.sh Phase 6, window/move.sh, quick/actions.sh, quick/combo.sh.

#### `move_window_to_screen(uuid, screen_ref)` — screen.sh
- Resolves screen reference, calculates origin, calls `move_window`.
- **Callers:** core.sh Phase 6, window/move.sh, quick commands.

#### `move_window_to_position(uuid, screen_ref, position)` — screen.sh
- Supports 24+ position modes with relative-to-absolute coordinate calculation.
- **Callers:** core.sh Phase 6, window/move.sh, quick commands.
- **Impact:** Most complex function in the module. Position constant changes require updating the switch logic here.

#### `detect_window_screen(uuid)` — screen.sh
- Returns which screen a window is on based on its current position.
- **Callers:** window/move.sh, quick/picker.sh, quick/actions.sh.

#### `detect_window_position(uuid, output_num)` — screen.sh
- Returns named position with +/-5px tolerance matching.
- **Callers:** window/move.sh, quick/picker.sh, quick/actions.sh.

#### `validate_desktop_number(desktop)` — desktop.sh
- Checks range 1..DETECTED_DESKTOP_COUNT.
- Internal to desktop operations.

#### `refresh_screens()` — screen-detection.sh
- Wrapper for `detect_screens()`. Rarely called.

#### `list_detected_screens()` — screen-detection.sh
- Display function for human output.
- **Callers:** `screen_list` command.

### Tier 3 — Low Impact (internal helpers, rarely changed)

- `calculate_screen_origin(screen_ref)` in screen.sh — Returns X,Y of screen top-left. Internal to move_to_screen/position.
- `validate_screen_number()` / `validate_screen_reference()` in screen.sh — Validation helpers.
- `resolve_position(input)` in screen.sh — Position abbreviation/name resolution. Used by quick/combo.sh.
- `get_desktop_for_window()` / `get_current_desktop()` / `set_current_desktop()` in desktop.sh — Desktop query wrappers.
- `db_set_screen_alias()`, `db_remove_screen_alias()`, `db_get_screen_alias()`, `db_list_screen_aliases()`, `db_get_aliases_for_target()`, `db_get_all_screen_aliases()` in db/screen.sh — Alias CRUD operations.
- `screen_command()`, `screen_list()`, `screen_alias()` in commands/screen/*.sh — Command handlers.

## Global State

| Variable | Type | Set By | Used By |
|----------|------|--------|---------|
| `DETECTED_SCREEN_COUNT` | integer | `detect_screens()` | Screen validation everywhere |
| `SCREEN_OUTPUT_IDS[]` | indexed array | `detect_screens()` | Screen iteration |
| `SCREEN_INFO[]` | associative array | `detect_screens()` | All coordinate lookups via `get_screen_info()` |
| `DETECTED_DESKTOP_COUNT` | integer | `detect_desktops()` | Desktop validation everywhere |

## External Tool Dependencies

| Tool | Used By | Purpose |
|------|---------|---------|
| `kscreen-doctor` (--json) | `detect_screens()` | Screen geometry discovery |
| `kdotool` | `detect_desktops()`, `move_window_to_desktop()`, desktop queries | Desktop count, window-to-desktop assignment, desktop switching |

## Cross-Module Dependencies

| Module | Dependency Direction | Details |
|--------|---------------------|---------|
| **Core Engine** (core.sh) | core --> screen/desktop | Uses all positioning/desktop functions in Phase 6 of window launch |
| **Window Management** (window.sh) | screen <--> window | screen.sh calls `move_window`, `size_window`, `get_window_position`, `get_window_size` |
| **Workspace** (create/edit/import) | workspace --> screen/desktop | Validates desktop and screen references during definition |
| **Quick Commands** | quick --> screen/desktop | `detect_window_screen`/`detect_window_position`, all move operations |
| **Window Commands** (window/move.sh) | window_cmd --> screen/desktop | Move command uses all detection and move functions |
| **Database** (db/screen.sh) | screen --> db | Screen aliases via alias CRUD functions |

## Change Checklist

When modifying this module, verify the following:

- [ ] **Changing `detect_screens()` parsing?** Confirm `SCREEN_INFO[]` key format is unchanged or update all `get_screen_info()` callers.
- [ ] **Changing `resolve_screen_reference()` resolution order?** Test with numeric refs, name refs, and alias refs (including chained aliases).
- [ ] **Changing position constants or adding positions?** Update `move_window_to_position()` switch logic and `resolve_position()` abbreviation map.
- [ ] **Changing `move_window_to_position()` coordinate math?** Test all 24+ position modes on single-screen and multi-screen setups.
- [ ] **Changing detection tolerance in `detect_window_position()`?** Currently +/-5px — affects quick command position matching.
- [ ] **Changing desktop validation range?** Confirm `DETECTED_DESKTOP_COUNT` is set before validation runs.
- [ ] **Changing screen alias DB schema?** Update all 6 functions in db/screen.sh and the alias command handler.
- [ ] **Adding new external tool calls?** Update `lib/utils/checks.sh` dependency checks.
- [ ] **Modifying global state variables?** Ensure `bin/kdoitall` startup sequence still populates them before any consumer runs.
- [ ] **Test with `--verbose`** to confirm debug output still traces correctly through detection and positioning flows.
