# App Registry Module -- Codebase Impact Map

## 1. Overview

The app registry module handles application discovery, metadata management, and launch configuration for kdoitall. It scans system `.desktop` files, loads app-specific metadata from JSON definitions, validates structure and functions, and persists everything to the SQLite database. This module is the foundation for workspace creation -- without a registered app and its launch options, no workspace window entry can be created.

The module spans three concerns: **scanning/registration** (discovering apps and storing them), **definition loading** (parsing per-app metadata.json and sourcing launch functions), and **command interface** (the `kdoitall app` subcommand family).

---

## 2. Key Files

| File | Purpose |
|------|---------|
| `lib/app/registry.sh` | Application scanning, validation, launch option storage, terminal emulator detection |
| `lib/app-definitions/loader.sh` | Loads app metadata into globals: APP_ID, TERMINAL_COMMAND, LAUNCH_TYPE (1 function) |
| `lib/app-definitions/validator.sh` | JSON structure and function validation (4 functions, incl. shared metadata) |
| `lib/app-definitions/json-parser.sh` | jq-based metadata extraction (10 functions) |
| `lib/app-definitions/apps/<app_id>/metadata.json` | Per-app config: terminal_command, launch_options with PascalCase parameters |
| `lib/app-definitions/apps/<app_id>/functions.sh` | Per-app guard, load_app_metadata call, launch function implementations |
| `lib/app-definitions/shared/terminal-emulator/metadata.json` | Shared launch options for all terminal emulators |
| `lib/app-definitions/shared/terminal-emulator/functions.sh` | Shared terminal launch functions (terminal_run_command_in_directory, terminal_run_script, terminal_launch_dev_server) |
| `lib/app-definitions/apps/code/functions.sh` | VS Code: launch_code_window, launch_code_workspace_window |
| `lib/app-definitions/apps/org.mozilla.firefox/functions.sh` | Firefox: launch_firefox_window |
| `lib/db/terminal-emulator.sh` | CRUD operations for terminal_emulators table |
| `lib/commands/app/dispatcher.sh` | Routes `kdoitall app` subcommands |
| `lib/commands/app/scan.sh` | Entry point for `kdoitall app scan` |
| `lib/commands/app/info.sh` | App info display (includes terminal emulator status) |
| `lib/commands/app/list.sh` | App listing with filters |
| `lib/commands/app/options.sh` | Launch options display |
| `lib/commands/app/validate.sh` | Validate all app definition files |
| `lib/commands/app/set-terminal.sh` | Mark/unmark apps as terminal emulators |
| `lib/commands/app/safe-mode.sh` | Safe-mode command (skip/reset/interactive) |

---

## 3. Function Impact Map

### Tier 1 -- Wide Blast Radius

These functions are load-bearing. Changes here cascade across the entire app ecosystem.

**`registry_scan_applications()`** -- `lib/app/registry.sh`

Scans system `.desktop` file locations (`DESKTOP_FILE_LOCATIONS[]`), extracts app metadata, merges reference registry data, and stores everything to the database. This is the single entry point for populating the application table.

- Database writes: `db_upsert_application_scan` (INSERT/UPDATE on `applications`), `db_remove_uninstalled_applications` (DELETE from `applications`), `db_upsert_terminal_emulator` (INSERT/REPLACE on `terminal_emulators`)
- Module calls: `validate_app_id_format`, `registry_check_app_files`, `registry_get_app_directory_path`, `json_get_all_metadata`, `registry_store_launch_options`, `registry_store_shared_terminal_launch_options`, `app_registry_exists`, `app_registry_get_metadata`, `db_is_terminal_emulator`, `db_upsert_terminal_emulator`
- Terminal emulator detection: Checks `.desktop` Categories for `TerminalEmulator` and reference registry `is_terminal_emulator` column. Auto-registers shared terminal launch options for detected emulators.
- Callers: `app_scan` in `lib/commands/app/scan.sh`
- Impact: Entire application discovery depends on this. Changes affect what apps are available for workspaces. If scan breaks, no new apps can be registered.

**`load_app_metadata(app_dir)`** -- `lib/app-definitions/loader.sh`

Sets global variables `APP_ID`, `TERMINAL_COMMAND`, and `LAUNCH_TYPE` from the app's `metadata.json`. Called at source time by every app `functions.sh` file.

- Callers: Every app definition file (`lib/app-definitions/apps/*/functions.sh`), including `code/functions.sh`, `org.mozilla.firefox/functions.sh`, and all future app definitions
- Impact: All terminal-launch apps depend on this initialization. A breaking change here breaks every app definition simultaneously.

**`registry_store_launch_options(app_id, app_dir)`** -- `lib/app/registry.sh`

Parses `metadata.json` for the given app and writes launch options and their parameters to the database. Performs a delete-then-insert cycle.

- Database writes: `db_delete_launch_options_for_app` (DELETE from `launch_options`), `db_add_launch_option` (INSERT into `launch_options`), `db_get_launch_option_id` (READ from `launch_options`), `db_add_launch_parameter` (INSERT into `launch_parameters`)
- Callers: `registry_scan_applications` (during scan)
- Impact: Launch options are required for workspace script generation. If options are not stored correctly, workspace open/close scripts cannot be compiled.

**`registry_store_shared_terminal_launch_options(app_id)`** -- `lib/app/registry.sh`

Reads `lib/app-definitions/shared/terminal-emulator/metadata.json` and registers shared launch options under the given terminal emulator's app_id. Called during scan for each detected terminal emulator. Options are appended after any per-app launch options (display_order continues from the max existing order). Also sets `has_terminal_launch=TRUE` on the applications table.

- Database writes: `db_add_launch_option` (INSERT into `launch_options`), `db_add_launch_parameter` (INSERT into `launch_parameters`), UPDATE `applications.has_terminal_launch`
- Callers: `registry_scan_applications` (during scan), `app_set_terminal` (manual classification)

---

### Tier 2 -- Moderate Blast Radius

Changes here affect validation, command routing, or safe-mode workflows but do not break core scanning or launching.

**`registry_validate_app_metadata(app_dir)`** -- `lib/app/registry.sh`

Validates a single app's `metadata.json` structure and confirms that declared functions exist in the corresponding `functions.sh`.

- Calls: `json_validate_metadata`, `json_validate_parameters`, `json_get_launch_options_count`, `json_validate_function_exists`
- Callers: `registry_validate_all_app_files`

**`registry_validate_all_app_files()`** -- `lib/app/registry.sh`

Iterates all app directories under `lib/app-definitions/apps/` and validates each one.

- Callers: `app_validate` command in `lib/commands/app/validate.sh`

**`json_validate_metadata(json_file)`** -- `lib/app-definitions/validator.sh`

Single jq call that validates required fields exist, parameter names use PascalCase, and descriptions are non-empty.

- Callers: `registry_validate_app_metadata`

**`json_get_all_launch_options(json_file)`** -- `lib/app-definitions/json-parser.sh`

Returns TSV output: `function_name\tdescription\tparams_json`. Primary data extraction path for launch option storage.

- Callers: `registry_store_launch_options`

**`app_command()`** -- `lib/commands/app/dispatcher.sh`

Routes subcommands: `scan`, `list|ls`, `info|i`, `validate`, `options|opts`, `safe-mode|sm`. Filters `--verbose`/`--info` flags before dispatching.

- Callers: Main command dispatcher in `bin/kdoitall`

**`app_safe_mode(subcommand, app_id)`** -- `lib/commands/app/safe-mode.sh`

Interactive validation menu plus skip/reset subcommands for safe-mode window class detection.

- Database: `db_application_exists`, `db_get_display_name`, `db_set_safe_mode_completed`, `db_clear_safe_mode_data`, `db_count_pending_safe_mode_apps`, `db_get_pending_safe_mode_apps`
- Module calls: `safe_mode_launch_and_detect` (window management)

---

### Tier 3 -- Narrow Blast Radius

Internal helpers and thin command wrappers. Changes here are generally isolated.

**Registry helpers** (`lib/app/registry.sh`):
- `registry_check_app_files(app_id)` -- Checks if app directory with `metadata.json`/`functions.sh` exists. Internal to scan.
- `registry_get_app_directory_path(app_id)` -- Returns normalized path to app definition directory. Internal helper.

**JSON parser functions** (`lib/app-definitions/json-parser.sh`):
- `json_get_terminal_command(json_file)` -- Extracts terminal_command field
- `json_get_launch_options_count(json_file)` -- Returns count of launch options
- `json_get_launch_option_function_name(json_file, index)` -- Function name at index
- `json_get_launch_option_description(json_file, index)` -- Description at index
- `json_get_function_parameters(json_file, func_name)` -- Parameters for a function
- `json_get_launch_options(json_file)` -- All launch option names
- `json_get_launch_option_parameters(json_file, index)` -- Parameters at index
- `json_pretty_print(json_file)` -- Pretty-printed JSON output
- `json_get_all_metadata(json_file)` -- All metadata fields in one call

**Validator helpers** (`lib/app-definitions/validator.sh`):
- `json_validate_function_exists(functions_file, func_name)` -- Greps for function declaration in shell file
- `json_validate_parameters(json_file)` -- Backward compatibility stub, always returns 0

**Command wrappers** (`lib/commands/app/*.sh`):
- `app_scan()` -- Calls `registry_scan_applications`
- `app_info()` -- Calls display utilities with DB data
- `app_list()` -- Calls display utilities with filter
- `app_options()` -- Calls display utilities for launch options
- `app_validate()` -- Calls `registry_validate_all_app_files`

---

## 4. Database Tables

| Table | Operations | Access Points |
|-------|-----------|---------------|
| `applications` | READ/WRITE during scan, READ during info/list/safe-mode | `lib/db/app.sh` |
| `launch_options` | WRITE during scan (delete+insert, incl. shared terminal options), READ during options display and workspace script generation | `lib/db/launch-options.sh` |
| `launch_parameters` | WRITE during scan, READ during options display and workspace script generation | `lib/db/launch-options.sh` |
| `terminal_emulators` | WRITE during scan and `set-terminal` command, READ during terminal launch and info display | `lib/db/terminal-emulator.sh` |
| `app_registry` (separate DB) | READ during scan for reference metadata (incl. `is_terminal_emulator`, `terminal_exec_flag`) | `lib/db/app-registry.sh` |

Key write patterns:
- **Scan** performs upsert on `applications`, delete-then-insert on `launch_options` and `launch_parameters`
- **Safe-mode** writes to `applications` (safe_mode_completed flag, window class data)
- **Workspace commands** only read from these tables

---

## 5. Cross-Module Dependencies

| Dependency | Direction | Interface |
|-----------|-----------|-----------|
| **Core Engine** (`lib/core/core.sh`) | App definitions call into core | `execute_launch_window` -- the launch lifecycle function called by every app's launch function |
| **Database** (`lib/db/app.sh`, `lib/db/launch-options.sh`, `lib/db/app-registry.sh`) | Registry writes/reads to DB | All persistence for applications, launch options, launch parameters, reference registry |
| **Window Management** (`lib/window-management/window.sh`) | Safe-mode uses window ops | `get_window_class`, `get_window_pid`, `close_window`, `minimize_window` |
| **Display Utilities** (`lib/utils/display.sh`) | Command handlers call display | `display_application_info`, `display_applications_list`, `display_launch_options`, `parse_window_title_segments` |
| **Validators** (`lib/utils/validators.sh`) | Registry calls validators | `validate_app_id_format`, `validate_parameter_pass`, `validate_file_exists`, `validate_directory_exists` |
| **Workspace Commands** | Workspace reads app data | Workspace create/edit reads `launch_options` for function selection; workspace open triggers safe-mode if needed |

**Constants used across the module:**
- `LAUNCH_MODE_MULTI`, `LAUNCH_MODE_SINGLE`, `LAUNCH_MODE_UNIQUE`, `LAUNCH_MODE_UNKNOWN`, `LAUNCH_MODE_SINGLE_OR_UNIQUE`
- `LAUNCH_TYPE_TERMINAL`, `LAUNCH_TYPE_DESKTOP`
- `DESKTOP_FILE_LOCATIONS[]` -- System `.desktop` file directories
- `LIB_DIR` -- Path to lib directory

---

## 6. Change Checklist

Use this checklist when modifying files in the app registry module.

### If changing `metadata.json` schema or structure:
- [ ] Update `json_validate_metadata()` in `lib/app-definitions/validator.sh`
- [ ] Update all `json_get_*` functions in `lib/app-definitions/json-parser.sh` that read affected fields
- [ ] Update `load_app_metadata()` in `lib/app-definitions/loader.sh` if globals change
- [ ] Update `registry_store_launch_options()` in `lib/app/registry.sh` if launch option structure changes
- [ ] Update every existing `metadata.json` in `lib/app-definitions/apps/*/`
- [ ] Run `kdoitall app validate` to verify all definitions

### If changing launch function signatures:
- [ ] Update all existing launch functions in `lib/app-definitions/apps/*/functions.sh`
- [ ] Update `execute_launch_window` call pattern in `lib/core/core.sh` if core signature changes
- [ ] Update workspace script generation to pass new parameters
- [ ] Re-scan with `kdoitall app scan` to refresh stored launch options

### If changing the scan pipeline (`registry_scan_applications`):
- [ ] Verify `DESKTOP_FILE_LOCATIONS[]` still covers all system paths
- [ ] Test that `db_upsert_application_scan` handles both new and existing apps
- [ ] Test that `db_remove_uninstalled_applications` does not remove apps with active workspace entries
- [ ] Verify `registry_store_launch_options` delete-then-insert does not orphan workspace references

### If adding a new app definition:
- [ ] Create `lib/app-definitions/apps/<app_id>/metadata.json` with required fields
- [ ] Create `lib/app-definitions/apps/<app_id>/functions.sh` with source guard and `load_app_metadata` call
- [ ] Ensure parameter names in `metadata.json` use PascalCase
- [ ] Implement all launch functions declared in `metadata.json`
- [ ] Run `kdoitall app validate` to check structure
- [ ] Run `kdoitall app scan` to register the app

### If changing database schema for app-related tables:
- [ ] Update `database/schema.sql`
- [ ] Update all `db_*` functions in `lib/db/app.sh` and `lib/db/launch-options.sh`
- [ ] Update `registry_scan_applications()` and `registry_store_launch_options()` if column changes affect scan
- [ ] Update display functions in `lib/utils/display.sh`
- [ ] Update workspace script generation if it reads affected columns
- [ ] Test migration path for existing databases

### If changing the command interface (`kdoitall app`):
- [ ] Update routing in `lib/commands/app/dispatcher.sh`
- [ ] Add/update the command handler in `lib/commands/app/<subcommand>.sh`
- [ ] Update help text and usage output
- [ ] Verify `--verbose`/`--info` flag filtering in dispatcher
