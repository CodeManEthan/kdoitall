# Database Module — Codebase Impact Map

## 1. Overview

The database module provides all persistent storage and query capabilities for kdoitall. It manages two separate SQLite databases: the **main database** (workspace definitions, window tracking, application metadata, screen aliases) and a **read-only app registry database** (seed data for application scanning). All SQL execution flows through a Python coproc server (`db-server.py`) that Bash communicates with via file descriptors, exposing results through global state arrays (`DB_STATUS`, `DB_RESULT[]`, `DB_ERROR`).

The module spans 11 files: one schema definition, one registry seed file, and nine Bash library files organized across `lib/core/`, `lib/db/`, and `database/`.

## 2. Key Files

| File | Description |
|------|-------------|
| `database/schema.sql` | Schema definition for the main database (8 tables, triggers, indexes) |
| `database/app-registry.sql` | Seed data for the read-only app registry database |
| `lib/core/database.sh` | Database helper utilities (normalize_boolean) |
| `lib/db/helpers.sh` | Core DB client infrastructure: Python coproc lifecycle, db_query, db_registry_query |
| `lib/db/app-registry.sh` | Query functions for the read-only app registry database |
| `lib/db/app.sh` | Full CRUD for the applications table (~61 functions) |
| `lib/db/launch-options.sh` | CRUD for launch_options and launch_parameters tables |
| `lib/db/terminal-emulator.sh` | CRUD for terminal_emulators table |
| `lib/db/screen.sh` | Screen alias management (screen_aliases table) |
| `lib/db/window-definitions.sh` | CRUD for window_definitions table (workspace window templates) |
| `lib/db/window-info.sh` | Query functions for window information and state |
| `lib/db/window-tracking.sh` | Tracking and management of live window instances (app_windows table) |

## 3. Function Impact Map

### Tier 1 — Wide Blast Radius

These functions are called from many modules across the codebase. Changes here risk cascading breakage.

| Function | File | Tables Touched | Callers |
|----------|------|----------------|---------|
| `db_query(sql, [params...])` | `lib/db/helpers.sh` | Any (executes arbitrary SQL) | Every `lib/db/*` file; indirectly every command in the system |
| `db_get_app_launch_properties(app_id)` | `lib/db/app.sh` | `applications` (SELECT) | `lib/core/core.sh` (launch_by_app_id), every app definition file (`lib/app-definitions/apps/*/functions.sh`) |
| `db_add_window(workspace, window_name, uuid, class, title)` | `lib/db/window-tracking.sh` | `app_windows` (INSERT) | `lib/core/core.sh` (execute_launch_window Phase 5) |
| `db_get_uuid(window_name)` | `lib/db/window-tracking.sh` | `app_windows` (SELECT) | `lib/core/core.sh` (execute_close_window), `lib/commands/window/close.sh`, `focus.sh`, `minimize.sh`, `status.sh`, `move.sh` |
| `db_delete_window(window_name)` | `lib/db/window-tracking.sh` | `app_windows` (DELETE) | `lib/core/core.sh` (execute_close_window), `lib/commands/workspace/close.sh`, `lib/commands/quick/actions.sh` |
| `db_claim_window(workspace, window_name, uuid, title)` | `lib/db/window-tracking.sh` | `app_windows` (UPDATE) | `lib/core/core.sh` (execute_launch_window Phase 2/5), `db_release_window_to_auto` |
| `db_workspace_exists(workspace_name)` | `lib/db/workspace.sh` | `workspace_definitions` (SELECT COUNT) | `lib/commands/workspace/open.sh`, `close.sh`, `edit.sh`, `delete.sh`, `info.sh`, `focus.sh`, `minimize.sh`, `export.sh`, `import.sh` |
| `db_list_window_definitions(workspace_name)` | `lib/db/window-definitions.sh` | `window_definitions` (SELECT) | `lib/workspace/generator.sh`, `lib/commands/workspace/edit.sh`, `lib/commands/workspace/export.sh` |

### Tier 2 — Moderate Blast Radius

These functions are called from a few specific modules. Changes require targeted testing.

| Function | File | Tables Touched | Callers |
|----------|------|----------------|---------|
| `db_server_start()` / `db_server_stop()` | `lib/db/helpers.sh` | None (coproc lifecycle) | `bin/kdoitall` at startup/shutdown |
| `db_registry_query(sql, [params...])` | `lib/db/helpers.sh` | `app_registry` (any SQL) | `lib/db/app-registry.sh` functions |
| `db_upsert_application_scan(...)` | `lib/db/app.sh` | `applications` (INSERT/UPDATE) | `lib/app/registry.sh` |
| `db_add_existing_windows()` | `lib/db/window-tracking.sh` | `app_windows` (batch INSERT via JSON) | `lib/core/core.sh` (auto_detect_windows) |
| `db_delete_stale_windows()` | `lib/db/window-tracking.sh` | `app_windows` (batch DELETE via JSON) | `lib/core/core.sh`, `lib/window-management/window.sh` |
| `db_get_all_windows()` | `lib/db/window-info.sh` | `app_windows` (SELECT) | `lib/core/core.sh`, `lib/window-management/window.sh` |
| `db_get_existing_window_uuids()` | `lib/db/window-info.sh` | `app_windows` (SELECT) | `lib/window-management/window.sh` |
| `db_create_workspace()` / `db_delete_workspace()` | `lib/db/workspace.sh` | `workspace_definitions` (INSERT/DELETE) | `lib/commands/workspace/create.sh`, `delete.sh`, `import.sh` |
| `db_get_workspace_windows_ordered(workspace)` | `lib/db/window-info.sh` | `app_windows` JOIN `window_definitions` (SELECT) | `lib/commands/workspace/close.sh`, `focus.sh`, `minimize.sh` |
| `db_set_safe_mode_results(...)` | `lib/db/app.sh` | `applications` (UPDATE) | `lib/app/safe-mode.sh` |
| `db_get_apps_needing_safe_mode(workspace, strictness)` | `lib/db/app.sh` | `applications` JOIN `window_definitions` (SELECT) | `lib/app/safe-mode.sh` |

### Tier 3 — Narrow Blast Radius

These functions are module-internal or called from a single location. Changes are low-risk.

| Function | File | Tables Touched | Callers |
|----------|------|----------------|---------|
| `normalize_boolean()` | `lib/core/database.sh` | None (utility) | `lib/db/*` functions internally |
| `db_get_window_name(uuid)` | `lib/db/window-tracking.sh` | `app_windows` (SELECT) | Internal lookups |
| `db_get_class(window_name)` | `lib/db/window-tracking.sh` | `app_windows` (SELECT) | Internal lookups |
| `db_get_window_title(window_name)` | `lib/db/window-tracking.sh` | `app_windows` (SELECT) | Internal lookups |
| `db_set_screen_alias()` | `lib/db/screen.sh` | `screen_aliases` (INSERT/UPDATE) | Screen commands |
| `db_remove_screen_alias()` | `lib/db/screen.sh` | `screen_aliases` (DELETE) | Screen commands |
| `db_get_screen_alias()` | `lib/db/screen.sh` | `screen_aliases` (SELECT) | `lib/core/screen-detection.sh` |
| `db_list_screen_aliases()` | `lib/db/screen.sh` | `screen_aliases` (SELECT) | Screen commands |
| `app_registry_exists()` | `lib/db/app-registry.sh` | `app_registry` (SELECT) | `lib/app/registry.sh` during scan |
| `app_registry_get_metadata()` | `lib/db/app-registry.sh` | `app_registry` (SELECT) | `lib/app/registry.sh` during scan |
| `app_registry_list_apps()` | `lib/db/app-registry.sh` | `app_registry` (SELECT) | `lib/app/registry.sh` during scan |
| `db_get_tab_by_tab_name()` | `lib/db/window-tracking.sh` | `tabs` (SELECT) | Rarely used |
| `db_set_post_launch_metadata(...)` | `lib/db/window-tracking.sh` | `applications` (UPDATE, conditional) | `lib/core/core.sh` (gather_post_launch_metadata) |
| `db_deactivate_empty_workspaces()` | `lib/db/workspace.sh` | `workspace_definitions` (UPDATE) | Workspace list and status commands |

## 4. Database Tables

### Main Database (KDOITALL_DB)

#### `workspace_definitions`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `workspace_name` | TEXT | **PK** | Unique workspace identifier |
| `description` | TEXT | | Human-readable description |
| `created_at` | TEXT | | Timestamp of creation |
| `last_opened` | TEXT | | Timestamp of last open |
| `is_active` | INTEGER | | Whether workspace is currently active |
| `focus_window_name` | TEXT | | Window to focus when workspace opens |

#### `app_windows`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `window_name` | TEXT | **PK** | Unique window identifier |
| `workspace_name` | TEXT | **FK** -> `workspace_definitions.workspace_name` | Owning workspace |
| `uuid` | TEXT | | KDE window UUID for kdotool |
| `class` | TEXT | | Detected window class |
| `window_title` | TEXT | | Current window title |

#### `tabs`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `tab_name` | TEXT | **PK** | Unique tab identifier |
| `window_name` | TEXT | **FK** -> `app_windows.window_name` | Parent window |
| `tab_number` | INTEGER | Auto-increment via trigger | Position within window |

#### `applications`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `app_id` | TEXT | **PK** | Application identifier (e.g., `code`, `org.mozilla.firefox`) |
| `display_name` | TEXT | | Human-readable name |
| `desktop_file_path` | TEXT | | Path to .desktop file |
| `app_directory_path` | TEXT | | Path to app definition directory |
| `terminal_command` | TEXT | | Binary name for terminal launch |
| `app_class` | TEXT | | Detected window class (cached) |
| `has_terminal_launch` | INTEGER | | Supports terminal launch |
| `has_desktop_launch` | INTEGER | | Supports desktop launch (gtk-launch) |
| `launch_mode` | TEXT | | MULTI, SINGLE, or UNIQUE |
| `window_title_pattern` | TEXT | | Regex for window title matching |
| `supports_pid_validation` | INTEGER | | Whether PID-based detection works |
| `process_name` | TEXT | | Process name for detection |
| `executable_path` | TEXT | | Full path to executable |
| `app_name` | TEXT | | Display name from desktop file |
| `launch_time_ms` | INTEGER | | Measured launch time in milliseconds |
| `launch_time_samples` | INTEGER | | Number of launch time measurements |
| `has_splash_window` | TEXT | | Whether app shows a splash window |
| `splash_duration_ms` | INTEGER | | Duration of splash screen |
| `safe_mode_completed` | INTEGER | | Whether safe mode profiling is done |
| `requires_safe_mode` | INTEGER | | Whether app needs safe mode profiling |
| `last_validated` | TEXT | | Timestamp of last validation |

#### `launch_options`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | **PK** AUTOINCREMENT | Unique option ID |
| `app_id` | TEXT | **FK** -> `applications.app_id` | Parent application |
| `function_name` | TEXT | | Bash function name to call |
| `description` | TEXT | | Human-readable description |
| `display_order` | INTEGER | | Sort order for display |

#### `launch_parameters`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | **PK** AUTOINCREMENT | Unique parameter ID |
| `app_id` | TEXT | | Parent application |
| `function_id` | INTEGER | **FK** -> `launch_options.id` | Parent launch option |
| `parameter_name` | TEXT | | Parameter name |
| `description` | TEXT | | Human-readable description |
| `display_order` | INTEGER | | Sort order for display |

#### `terminal_emulators`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `app_id` | TEXT | **PK**, **FK** -> `applications.app_id` | Terminal emulator application |
| `exec_flag` | TEXT | NOT NULL, DEFAULT '-e' | CLI flag for command execution (e.g., `-e`, `--`, `start --`) |
| `detection_source` | TEXT | NOT NULL, DEFAULT 'auto' | How classified: `auto` (.desktop Categories), `registry` (reference DB), `manual` (user-set) |

#### `screen_aliases`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `alias` | TEXT | **PK** | Alias name (e.g., `left`, `right`) |
| `target` | TEXT | | Actual screen identifier |

#### `window_definitions`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `window_name` | TEXT | **PK** | Unique window template name |
| `workspace_name` | TEXT | **FK** -> `workspace_definitions.workspace_name` | Parent workspace |
| `app_id` | TEXT | **FK** -> `applications.app_id` | Application to launch |
| `launch_function` | TEXT | | Function name from launch_options |
| `desktop` | TEXT | | Target virtual desktop |
| `screen` | TEXT | | Target screen |
| `position` | TEXT | | Window position (FULLSCREEN, LEFTHALF, etc.) |
| `parameters` | TEXT | | Serialized launch parameters |
| `display_order` | INTEGER | | Launch order within workspace |

### Foreign Key Relationships

```
workspace_definitions
    |
    +--< app_windows.workspace_name
    |
    +--< window_definitions.workspace_name

applications
    |
    +--< launch_options.app_id
    |
    +--< window_definitions.app_id

launch_options
    |
    +--< launch_parameters.function_id

app_windows
    |
    +--< tabs.window_name
```

### App Registry Database (KDOITALL_REGISTRY_DB)

#### `app_registry`

| Column | Type | Description |
|--------|------|-------------|
| `app_id` | TEXT | Application identifier |
| `app_name` | TEXT | Display name |
| `app_class` | TEXT | Window class |
| `launch_mode` | TEXT | MULTI, SINGLE, or UNIQUE |
| `window_title_pattern` | TEXT | Regex for window title matching |
| `supports_pid_validation` | INTEGER | Whether PID-based detection works |
| `process_name` | TEXT | Process name for detection |
| `has_splash_window` | TEXT | Whether app shows a splash window |
| `splash_duration_ms` | INTEGER | Duration of splash screen |

## 5. Cross-Module Dependencies

This section documents which modules outside `lib/db/` call into the database module and why.

| Caller Module | File(s) | Functions Called | Purpose |
|---------------|---------|-----------------|---------|
| **Core Engine** | `lib/core/core.sh` | `db_add_window`, `db_claim_window`, `db_delete_window`, `db_get_all_windows`, `db_delete_stale_windows`, `db_add_existing_windows`, `db_get_app_launch_properties`, `db_set_app_class`, `db_set_has_splash_window`, `db_set_post_launch_metadata`, `db_get_app_metadata_status` | Window lifecycle (launch, detect, close), app metadata caching |
| **Window Management** | `lib/window-management/window.sh` | `db_get_all_windows`, `db_delete_stale_windows`, `db_get_existing_window_uuids` | Window state reconciliation and stale cleanup |
| **App Registry** | `lib/app/registry.sh` | `db_upsert_application_scan`, `db_remove_uninstalled_applications`, `db_add_launch_option`, `db_delete_launch_options_for_app`, `db_add_launch_parameter`, `db_get_launch_option_id` | Application scanning and registration |
| **Safe Mode** | `lib/app/safe-mode.sh` | `db_get_display_name`, `db_set_safe_mode_results`, `db_get_apps_needing_safe_mode`, `db_mark_apps_requiring_safe_mode`, `db_set_launch_time`, `db_get_launch_time`, `db_set_safe_mode_completed`, `db_clear_safe_mode_data`, `db_count_pending_safe_mode_apps`, `db_get_pending_safe_mode_apps` | Profiling app launch behavior and storing results |
| **Workspace Commands** | `lib/commands/workspace/*.sh` | `db_workspace_exists`, `db_create_workspace`, `db_delete_workspace`, `db_mark_workspace_opened`, `db_set_workspace_active`, `db_get_workspace`, `db_list_workspaces`, `db_get_workspace_focus_window`, `db_set_workspace_focus_window` | Workspace CRUD and state management |
| **Window Commands** | `lib/commands/window/*.sh` | `db_get_uuid`, `db_delete_window`, `db_get_window_info_by_uuid`, `db_list_tracked_windows` | Individual window operations by name/UUID |
| **Screen Detection** | `lib/core/screen-detection.sh` | `db_get_screen_alias` | Resolving screen aliases to hardware identifiers |
| **Display Utilities** | `lib/utils/display.sh` | `db_list_tracked_windows`, `db_get_active_workspace_windows`, `db_get_untracked_windows`, `db_get_launch_options`, `db_get_launch_parameters`, `db_get_active_workspace_window_status`, `db_get_quick_window_list` | Formatting data for user-facing output |
| **App Definitions** | `lib/app-definitions/apps/*/functions.sh` | `db_get_app_launch_properties` | Retrieving launch metadata before executing launch |
| **Main Entry Point** | `bin/kdoitall` | `db_server_start`, `db_server_stop` | Python coproc lifecycle management |
| **Workspace Generator** | `lib/workspace/generator.sh` | `db_list_window_definitions` | Reading window templates to generate open/close scripts |

## 6. Change Checklist

Use this checklist when modifying the database module. Check every item that applies to your change.

### Schema Changes

- [ ] Update `database/schema.sql` with new/modified table definitions
- [ ] Update `database/app-registry.sql` if registry table changes
- [ ] Verify all triggers and indexes are consistent with new schema
- [ ] Check foreign key constraints still hold
- [ ] Test with a fresh database (delete and recreate)

### Query Function Changes

- [ ] `lib/db/helpers.sh` — If changing query infrastructure, coproc protocol, or global state arrays
- [ ] `lib/db/app.sh` — If changing applications table queries (~61 functions to audit)
- [ ] `lib/db/app-registry.sh` — If changing registry database queries
- [ ] `lib/db/launch-options.sh` — If changing launch_options or launch_parameters queries
- [ ] `lib/db/screen.sh` — If changing screen_aliases queries
- [ ] `lib/db/window-definitions.sh` — If changing window_definitions queries
- [ ] `lib/db/window-info.sh` — If changing window query/join logic
- [ ] `lib/db/window-tracking.sh` — If changing app_windows tracking logic
- [ ] `lib/core/database.sh` — If changing normalize_boolean or adding shared DB utilities

### Cross-Module Impact

- [ ] `lib/core/core.sh` — If changing db_add_window, db_claim_window, db_delete_window, db_get_app_launch_properties, or window metadata functions
- [ ] `lib/window-management/window.sh` — If changing db_get_all_windows, db_delete_stale_windows, db_get_existing_window_uuids
- [ ] `lib/app/registry.sh` — If changing db_upsert_application_scan, launch option CRUD, or db_remove_uninstalled_applications
- [ ] `lib/app/safe-mode.sh` — If changing safe mode or launch time functions in app.sh
- [ ] `lib/commands/workspace/*.sh` — If changing workspace existence checks, CRUD, or state functions
- [ ] `lib/commands/window/*.sh` — If changing db_get_uuid, db_delete_window, or window info lookups
- [ ] `lib/core/screen-detection.sh` — If changing db_get_screen_alias return format
- [ ] `lib/utils/display.sh` — If changing any function used for display formatting
- [ ] `lib/app-definitions/apps/*/functions.sh` — If changing db_get_app_launch_properties return format
- [ ] `bin/kdoitall` — If changing db_server_start/db_server_stop interface
- [ ] `lib/workspace/generator.sh` — If changing db_list_window_definitions return format

### Testing

- [ ] Run `./scripts/show-database-schema.sh` to verify schema is correct
- [ ] Run `./scripts/show-database.sh` to verify data integrity
- [ ] Run `kdoitall app scan` to test application registration path
- [ ] Run `kdoitall --verbose --test-open` to test window launch path
- [ ] Run `kdoitall --verbose --test-close` to test window close path
- [ ] Run `kdoitall app validate` to verify app definitions still work
