# Workspace Module — Codebase Impact Map

## 1. Overview

The workspace module is the central orchestration layer of kdoitall. It handles the full lifecycle of workspaces: creation (interactive and file-based), editing, script generation, opening, closing, focus management, and export/import. Workspace definitions are stored in SQLite and compiled into standalone bash scripts that drive the core window launch engine at runtime.

---

## 2. Key Files

| File | Purpose | Size/Complexity |
|------|---------|-----------------|
| `lib/commands/workspace/dispatcher.sh` | Subcommand routing (`create`, `open`, `close`, `edit`, etc.) | Low |
| `lib/commands/workspace/create.sh` | Interactive workspace creation via 9-state state machine | 1041 lines, High |
| `lib/commands/workspace/edit.sh` | Interactive workspace editing (add/edit/remove windows) | 507 lines, High |
| `lib/commands/workspace/open.sh` | Workspace opening with safe-mode integration | Medium |
| `lib/commands/workspace/close.sh` | 4-phase close process with assisted close for stubborn windows | Medium |
| `lib/commands/workspace/import.sh` | JSON import with full validation pipeline | Medium |
| `lib/commands/workspace/export.sh` | JSON export to stdout | Low |
| `lib/commands/workspace/delete.sh` | Workspace deletion with confirmation | Low |
| `lib/commands/workspace/list.sh` | Workspace listing with optional details | Low |
| `lib/commands/workspace/info.sh` | Workspace info display | Low |
| `lib/commands/workspace/focus.sh` | Raise and focus all workspace windows | Low |
| `lib/commands/workspace/minimize.sh` | Minimize all workspace windows | Low |
| `lib/workspace/generator.sh` | Script generation and window definition persistence | High |
| `lib/db/workspace.sh` | Workspace CRUD operations (19 functions) | Medium |
| `lib/db/window-definitions.sh` | Window definition CRUD operations (7 functions) | Low |

---

## 3. Function Impact Map

### Tier 1 — Wide Blast Radius

Changes to these functions risk breaking all workspace operations.

| Function | File | What It Does | Callers | Why It Matters |
|----------|------|-------------|---------|----------------|
| `generate_workspace_scripts(workspace_name)` | `generator.sh` | Generates standalone bash script at `WORKSPACE_SCRIPTS_DIR`. Calls `generate_workspace_script` (template), `store_window_definitions` (persist to DB), `chmod`. Consumes `WORKSPACE_APPS[]` array (format: `app_id\|window_name\|launch_function\|desktop\|screen\|position\|parameters`). Sources app definition files for terminal apps; uses `launch_by_app_id` for desktop apps. | `workspace_create`, `workspace_edit` (`_edit_save`), `workspace_create_from_file` | Every workspace depends on generated scripts. Changes here break all workspace open/close operations. |
| `workspace_open([--skip] workspace_name)` | `open.sh` | Sources generated script and runs `open_workspace_$name()`. Performs safe-mode check (`detect_safe_mode_apps`, `prompt_safe_mode`). Saves/restores active window focus. DB calls: `db_workspace_exists`, `db_mark_workspace_opened`, `db_get_workspace_focus_window`, `db_get_window_uuid_by_name`. Window calls: `get_active_window_uuid`, `activate_window`, `window_exists`. | `workspace_command` dispatcher | Primary user-facing operation. Changes affect the entire launch flow. |
| `workspace_close(workspace_name)` | `close.sh` | 4-phase close: (1) send close requests, (2) verify closed windows + DB cleanup, (3) interactive assisted close for stubborn windows with polling/retry/skip, (4) mark inactive + restore focus. DB calls: `db_get_workspace_windows_ordered`, `db_delete_window`, `db_release_window_to_auto`, `db_set_workspace_active`. Window calls: `close_window`, `refresh_current_windows`, `window_exists`, `window_not_exists`, `activate_window`. | `workspace_command` dispatcher | Counterpart to open. Incorrect changes can leave orphaned windows or stale DB records. |
| `workspace_create(workspace_name)` | `create.sh` | Interactive state machine with 9 states: `SELECT_APP` -> `WINDOW_NAME` -> `LAUNCH_TYPE` -> `DESKTOP` -> `SCREEN` -> `POSITION` -> `LAUNCH_FUNC` -> `PARAMETERS` -> `COMPLETE`. Supports `BACK`/`CHANGE_APP` navigation. Auto-generates window names. DB calls: `db_workspace_not_exists`, `db_create_workspace`, `db_set_workspace_focus_window`, `db_delete_workspace` (rollback). Calls `add_application_to_workspace` (loop), then `generate_workspace_scripts`. | `workspace_command` dispatcher | Primary workspace authoring path. Breakage here prevents users from creating workspaces. |
| `workspace_command()` | `dispatcher.sh` | Routes subcommands: `create\|new`, `list\|ls`, `info\|i`, `edit\|e`, `open\|o`, `close\|c`, `focus\|f`, `minimize\|min`, `delete\|rm`, `export\|exp`. Parses `--from-file`, `--replace`, `--skip` flags. Late-sources subcommand files on demand. | `bin/kdoitall` main dispatch | Single entry point for all workspace operations. Routing errors break entire subcommand trees. |

### Tier 2 — Moderate Blast Radius

Changes affect specific workflows but not the entire module.

| Function | File | What It Does | Callers |
|----------|------|-------------|---------|
| `workspace_create_from_file(workspace_name, file_path, replace_flag)` | `import.sh` | JSON import with full validation via `parse_and_validate_workspace_config`. Validates app existence, launch functions, window name uniqueness, desktop/screen/position resolution. Supports `--replace`. Calls `generate_workspace_scripts`. | `workspace_command` dispatcher (via `--from-file` flag) |
| `parse_and_validate_workspace_config(file_path, workspace_name, replace_flag)` | `import.sh` | Per-window validation: name format, app_id exists, function exists in launch_options, desktop range, screen reference resolution, position resolution. Uses `resolve_screen_reference`, `resolve_position_reference`. Populates `WORKSPACE_APPS[]`. | `workspace_create_from_file` |
| `workspace_edit(workspace_name)` | `edit.sh` | Interactive menu: edit description, add/edit/remove windows, save. Sources `create.sh` for helper functions. Calls `_edit_load_window_definitions`, `add_application_to_workspace`, `_edit_window`, `_edit_remove_window`, `_edit_save`. Save path calls `generate_workspace_scripts`. | `workspace_command` dispatcher |
| `store_window_definitions(workspace_name)` | `generator.sh` | Persists `WORKSPACE_APPS[]` to `window_definitions` table. DB calls: `db_delete_window_definitions_for_workspace`, `db_add_window_definition`. | `generate_workspace_scripts` |
| `add_application_to_workspace(workspace_name, display_order, apps_array_ref)` | `create.sh` | State machine for configuring a single window within a workspace. Calls `select_application`, `choose_launch_type`, `select_desktop`, `select_screen`, `select_position`, `select_launch_function` helpers. Returns result via array reference. | `workspace_create`, `workspace_edit` |
| `workspace_focus(workspace_name)` | `focus.sh` | Raises all live windows in display order, activates configured focus window (or last). DB calls: `db_get_workspace_windows_ordered`, `db_get_workspace_focus_window`, `db_get_window_uuid_by_name`. Window calls: `refresh_current_windows`, `window_exists`, `raise_window`, `activate_window`. | `workspace_command` dispatcher |
| `workspace_export(workspace_name)` | `export.sh` | JSON output to stdout. Includes workspace name, description, focus_window, and windows array with position variable expansion. DB calls: `db_get_workspace`, `db_get_workspace_focus_window`, `db_list_window_definitions`. | `workspace_command` dispatcher |

### Tier 3 — Narrow Blast Radius

Localized changes with limited ripple effects.

| Function | File | What It Does |
|----------|------|-------------|
| `generate_workspace_script(workspace_name, script_path)` | `generator.sh` | Template generation with source guard and conditional app sourcing |
| `workspace_delete(workspace_name)` | `delete.sh` | Confirm prompt + `db_delete_workspace` + remove script file |
| `workspace_list([--details])` | `list.sh` | `db_deactivate_empty_workspaces` + `db_list_workspaces` + display helpers |
| `workspace_info(workspace_name)` | `info.sh` | `db_get_workspace` + `display_workspace_windows` |
| `workspace_minimize(workspace_name)` | `minimize.sh` | Minimize all live windows for a workspace |
| `select_application()` | `create.sh` | App picker using `db_list_applications`, duplicate name detection, badge display |
| `choose_launch_type(app_id)` | `create.sh` | Auto-selects if only one launch type available |
| `select_desktop/screen/position/launch_function_with_retry()` | `create.sh` | Interactive selection helpers with BACK/CANCEL support |
| `_edit_load_window_definitions()` | `edit.sh` | Loads existing window definitions for editing |
| `_edit_window()` | `edit.sh` | Edit a single window's configuration |
| `_edit_remove_window()` | `edit.sh` | Remove a window from the workspace |
| `_edit_save()` | `edit.sh` | Save edited workspace and regenerate scripts |
| 19 `db_*` workspace functions | `lib/db/workspace.sh` | `db_create_workspace`, `db_update_workspace_description`, `db_delete_workspace`, `db_workspace_exists`, `db_workspace_not_exists`, `db_list_workspaces`, `db_get_workspace`, `db_set_workspace_last_opened`, `db_set_workspace_active`, `db_get_workspace_is_active`, `db_mark_workspace_opened`, `db_get_workspace_window_details`, `db_set_workspace_focus_window`, `db_get_workspace_focus_window`, `db_deactivate_empty_workspaces`, and others |
| 7 `db_*` window definition functions | `lib/db/window-definitions.sh` | `db_add_window_definition`, `db_get_window_definition`, `db_delete_window_definition`, `db_delete_window_definitions_for_workspace`, `db_list_window_definitions`, `db_window_definition_exists`, `db_get_workspace_app_ids` |

---

## 4. Database Tables

### `workspace_definitions` (owned by this module)

| Column | Type | Notes |
|--------|------|-------|
| `workspace_name` | TEXT | **Primary key** |
| `description` | TEXT | User-provided description |
| `created_at` | DATETIME | Auto-set on creation |
| `last_opened` | DATETIME | Updated by `db_mark_workspace_opened` |
| `is_active` | BOOLEAN | Tracks whether workspace is currently open |
| `focus_window_name` | TEXT | Window to activate after open/focus |

### `window_definitions` (owned by this module)

| Column | Type | Notes |
|--------|------|-------|
| `window_name` | TEXT | **Primary key** |
| `workspace_name` | TEXT | **FK -> workspace_definitions** |
| `app_id` | TEXT | **FK -> applications** |
| `launch_function` | TEXT | Function name or `launch_by_app_id` |
| `desktop` | INTEGER | Target virtual desktop |
| `screen` | TEXT | Target screen identifier |
| `position` | TEXT | Window position constant |
| `parameters` | TEXT | App-specific launch parameters |
| `display_order` | INTEGER | Order for open/close sequencing |

### `app_windows` (consumed by this module, owned by core engine)

| Column | Type | Notes |
|--------|------|-------|
| `window_name` | TEXT | **Primary key** |
| `workspace_name` | TEXT | **FK -> workspace_definitions** |
| `uuid` | TEXT | Runtime window UUID from kdotool |
| `class` | TEXT | Window class for detection |
| `window_title` | TEXT | Window title for detection |

---

## 5. Cross-Module Dependencies

### Modules This Module Depends On

| Module | Functions Used | Used By |
|--------|---------------|---------|
| **Core Engine** (`lib/core/`) | `execute_launch_window`, `execute_close_window`, `auto_detect_windows`, `launch_by_app_id` | Generated scripts (open/close), `workspace_open` |
| **Window Management** (`lib/core/`) | `activate_window`, `close_window`, `window_exists`, `window_not_exists`, `refresh_current_windows`, `raise_window`, `minimize_window`, `get_active_window_uuid` | `open.sh`, `close.sh`, `focus.sh`, `minimize.sh` |
| **Safe Mode** (`lib/core/`) | `detect_safe_mode_apps`, `prompt_safe_mode`, `safe_mode_launch_and_detect` | `open.sh` |
| **Database Layer** (`lib/db/`) | `workspace.sh` (19 funcs), `window-definitions.sh` (7 funcs), `window-tracking.sh`, `window-info.sh`, `app.sh` | All subcommands |
| **Screen Detection** (`lib/screen/`) | `DETECTED_DESKTOP_COUNT`, `SCREEN_INFO`, `resolve_screen_reference` | `create.sh`, `edit.sh`, `import.sh` |
| **Display** (`lib/display/`) | `display_workspace_windows`, `display_workspace_applications`, `display_status_active_workspaces` | `info.sh`, `list.sh`, `create.sh` |
| **Validators** (`lib/utils/`) | `validate_workspace_name`, `validate_window_name`, `validate_window_name_unique` | `create.sh`, `edit.sh`, `import.sh` |
| **Positions** (`lib/core/`) | `resolve_position_reference` | `import.sh` |
| **Application Registry** (`lib/applications/`) | App definition files sourced dynamically by `generator.sh` for terminal apps | `generator.sh` |

### Modules That Depend On This Module

| Consumer | Dependency |
|----------|-----------|
| `bin/kdoitall` | Calls `workspace_command()` from dispatcher |
| Generated scripts at `~/.local/share/kdoitall/workspaces/` | Produced by `generate_workspace_scripts`, consumed by `workspace_open` |

---

## 6. Change Checklist

Use this checklist when modifying workspace module code.

### Changing `generate_workspace_scripts` or `generate_workspace_script`
- [ ] Verify generated script template still sources all required libraries
- [ ] Test with both terminal-launch and desktop-launch apps
- [ ] Re-open an existing workspace to confirm backward compatibility
- [ ] Check that `store_window_definitions` still correctly persists `WORKSPACE_APPS[]` format
- [ ] Test create, edit, and import paths (all three call `generate_workspace_scripts`)

### Changing `workspace_open`
- [ ] Test with `--skip` flag
- [ ] Test safe-mode prompt flow (apps with splash windows)
- [ ] Verify focus window is restored after open
- [ ] Check `db_mark_workspace_opened` updates `last_opened` and `is_active`
- [ ] Test opening an already-active workspace

### Changing `workspace_close`
- [ ] Test all 4 phases: close requests, verification, assisted close, mark inactive
- [ ] Verify stubborn window polling/retry/skip behavior
- [ ] Confirm DB records are cleaned up (`db_delete_window`, `db_release_window_to_auto`)
- [ ] Test focus restoration after close
- [ ] Test closing a workspace with already-closed windows

### Changing `workspace_create` or `add_application_to_workspace`
- [ ] Test state machine navigation: forward, BACK, CHANGE_APP
- [ ] Verify auto-generated window names
- [ ] Test rollback on failure (`db_delete_workspace`)
- [ ] Confirm `generate_workspace_scripts` is called on completion
- [ ] Test with terminal-only, desktop-only, and both-type apps

### Changing `workspace_edit`
- [ ] Test add, edit, and remove window flows
- [ ] Verify `_edit_save` regenerates scripts correctly
- [ ] Confirm edit loads existing window definitions accurately
- [ ] Test editing a workspace that is currently active

### Changing import/export
- [ ] Test round-trip: export then import produces identical workspace
- [ ] Verify all validation in `parse_and_validate_workspace_config`
- [ ] Test `--replace` flag overwrites existing workspace
- [ ] Test with invalid JSON, missing fields, unknown app_ids, bad positions

### Changing `WORKSPACE_APPS[]` array format
- [ ] Update `generate_workspace_scripts` (consumer)
- [ ] Update `store_window_definitions` (consumer)
- [ ] Update `add_application_to_workspace` (producer)
- [ ] Update `_edit_load_window_definitions` (producer)
- [ ] Update `parse_and_validate_workspace_config` (producer)
- [ ] Update `workspace_export` if format affects export

### Changing workspace DB functions
- [ ] Check all callers across all subcommand files
- [ ] Verify schema compatibility with `database/schema.sql`
- [ ] Test with empty database (first-run scenario)
- [ ] Run `scripts/show-database.sh` to verify data integrity after changes

### Changing dispatcher routing
- [ ] Verify all aliases still work (`create|new`, `list|ls`, `info|i`, etc.)
- [ ] Test flag parsing (`--from-file`, `--replace`, `--skip`, `--details`)
- [ ] Confirm late-sourcing of subcommand files still works
- [ ] Update `bin/kdoitall` help text if subcommands change
