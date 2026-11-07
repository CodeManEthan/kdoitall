# Core Engine Module -- Codebase Impact Map

## 1. Overview

The core engine is the central nervous system of kdoitall. It contains the window launch/close pipeline (`core.sh`), all global constants and position definitions (`common.sh`), and the complete error code registry (`error-codes.sh`). Every workspace operation -- launching, positioning, closing, and detecting windows -- flows through this module. Changes here have the widest blast radius of any module in the system.

## 2. Key Files

| File | Purpose | Approximate Size |
|---|---|---|
| `lib/core/core.sh` | Central launch/close pipeline, window detection, auto-detect sync | Large -- multi-phase orchestrator |
| `lib/core/common.sh` | Global constants: positions, launch modes, timing, paths, blocklists | Medium -- foundational definitions |
| `lib/core/error-codes.sh` | ~232 error code constants and `ERROR_MESSAGES[]` associative array | Large -- exhaustive error catalog |

## 3. Function Impact Map

### Tier 1 -- Wide Blast Radius

These are load-bearing functions and constants. Changes affect nearly every module.

#### `execute_launch_window()` -- core.sh

The 15-parameter central launch pipeline. Every workspace launch flows through this function.

**Parameters:** `workspace, window_name, app_id, desktop, screen, position, launch_mode, launch_type, launch_fn, class, window_title_pattern, launch_time, launch_fn_arg, has_splash_window, splash_duration_ms`

**7 Phases:**

| Phase | Description | Key Calls |
|---|---|---|
| 1 -- Pre-launch snapshot | Synchronize DB with live windows | `auto_detect_windows` (populates `CURRENT_UUIDS` baseline) |
| 2 -- Single-instance shortcut | Skip launch if `LAUNCH_MODE_SINGLE` window exists | Jump directly to Phase 6 positioning |
| 3 -- Prepare and launch | Record pre-launch state, execute the launch function | `$launch_fn` (the app-specific launcher) |
| 4 -- Detect window | Mode-dependent detection strategy (see below) | `get_uuid_by_process_of_elimination_with_retry`, `get_active_window_uuid`, `get_window_class`, `get_window_title` |
| 4b -- Splash stability | Wait for splash to resolve, auto-learn splash status | `wait_for_stable_window`, `db_set_has_splash_window` |
| 5 -- Register window | Cache class if unknown, write UUID to DB | `detect_and_store_class`, `db_add_window` or `db_claim_window` |
| 6 -- Position window | Move to desktop, screen, and position | `move_window_to_desktop`, `move_window_to_screen`, `move_window_to_position` |
| 7 -- Background metadata | Non-blocking PID, title, timing collection | `gather_post_launch_metadata` |

**Detection methods by launch mode:**

| Launch Mode | Primary Strategy | Fallback |
|---|---|---|
| `SINGLE_OR_UNIQUE`, `UNKNOWN` | POE first (5s, 100ms intervals) | quick-check, then class/title fallback |
| `MULTI`, `UNIQUE` | quick-check first | POE (5s), then class/title fallback |

Detection result types: `new_window` (POE found fresh UUID), `existing_window` (existing window focused/found), `quick_check` (active window changed without count increase).

**Callers:** Every generated workspace script, every app definition launch function (`launch_code_window`, `launch_firefox_window`, etc.).

**Impact:** THE central function. Any change here affects every workspace launch in the system.

---

#### `auto_detect_windows()` -- core.sh

Synchronizes the database with live window state on the KDE desktop.

**Flow:** `refresh_current_windows` (populates `CURRENT_*` arrays) -> `db_get_all_windows` (loads `DB_*` arrays) -> `db_delete_stale_windows` (removes dead entries) -> `db_add_existing_windows` (registers newly discovered windows).

**Callers:** `execute_launch_window` (Phase 1), `launch_by_app_id`, `safe_mode_measure_launch_time`, `safe_mode_auto_detect_launch_mode`, `status_command`, `window_list`.

---

#### Constants -- common.sh

| Constant Group | Examples | Consumer Count |
|---|---|---|
| Position constants | `FULLSCREEN`, `RIGHTHALF`, `LEFTHALF`, `TOPHALF`, `BOTTOMHALF`, `TOPLEFT`, `TOPRIGHT`, `BOTTOMLEFT`, `BOTTOMRIGHT`, `LEFTTHIRD`, `MIDDLETHIRD`, `RIGHTTHIRD` (24+ total) | Every module that positions windows |
| Launch mode constants | `LAUNCH_MODE_MULTI`, `LAUNCH_MODE_SINGLE`, `LAUNCH_MODE_UNIQUE`, `LAUNCH_MODE_UNKNOWN`, `LAUNCH_MODE_SINGLE_OR_UNIQUE` | Core pipeline, app definitions, safe mode |
| Launch type constants | `LAUNCH_TYPE_TERMINAL`, `LAUNCH_TYPE_DESKTOP` | Core pipeline, app definitions, workspace scripts |
| Timing constants | `LAUNCH_DELAY`, `WINDOW_DELAY`, etc. | Core pipeline, detection logic |
| Path constants | `KDOITALL_DB`, `WORKSPACE_SCRIPTS_DIR` | Database module, workspace module, scripts |
| `SYSTEM_WINDOW_CLASSES[]` | 13 KDE system classes (`plasmashell`, `kwin`, etc.) | `is_transient_window` in window.sh |

**Callers:** Every module in the system uses these constants. Renaming or changing values is a system-wide event.

---

#### Error codes -- error-codes.sh

~232 error code constants and an `ERROR_MESSAGES[]` associative array mapping codes to human-readable strings.

**Callers:** Every module uses error codes for validation, early-return, and error reporting.

---

### Tier 2 -- Moderate Blast Radius

Changes here affect specific workflows but not the entire system.

#### `launch_by_app_id()` -- core.sh

High-level wrapper for desktop-launched (gtk-launch) applications.

**Flow:** `db_get_app_launch_properties` (retrieves class, title_pattern, launch_mode, launch_time, splash metadata) -> calls `execute_launch_window` with `_launch_via_gtk` as the launch function.

**Callers:** Generated workspace scripts (desktop launch type only).

---

#### `execute_close_window()` -- core.sh

Window close pipeline.

**Flow:** `db_get_uuid` (look up tracked UUID by window name) -> `close_window` (send close signal) -> `db_delete_window` (remove tracking entry).

**Callers:** `window_close` in `lib/commands/window/close.sh`.

---

#### `gather_post_launch_metadata()` -- core.sh

Non-blocking background data collection that runs after a window is launched and positioned.

**Collects:** PID validation (`get_window_pid`, `get_process_name`, `get_executable_path`), title pattern (`get_window_title`, `auto_select_title_pattern`), launch timing (rolling average with 50%/25% buffer).

**Database calls:** `db_get_app_metadata_status`, `db_set_post_launch_metadata`.

**Callers:** `execute_launch_window` (Phase 7).

---

#### `detect_and_store_class()` -- core.sh

Detects and caches the window class for an application.

**Flow:** `get_window_class` (from live window) -> `db_set_app_class` (persist to database).

**Callers:** `execute_launch_window` (Phase 5, only when class is unknown).

---

### Tier 3 -- Narrow Blast Radius

Changes here are isolated and low-risk.

| Function/Data | File | Purpose | Scope |
|---|---|---|---|
| `_launch_via_gtk(app_id)` | core.sh | Simple `gtk-launch` wrapper | Internal to `launch_by_app_id` only |
| `normalize_boolean(boolean)` | database.sh | TRUE/FALSE normalization | Internal to DB functions |
| `POSITION_MENU[]` | common.sh | Position selection menu labels | Create/edit/quick commands UI |
| `POSITION_MENU_ORDER[]` | common.sh | Ordered position list for menus | Create/edit/quick commands UI |
| `POSITION_ABBREVIATIONS[]` | common.sh | Short names for positions | Create/edit/quick commands UI |
| `SYSTEM_WINDOW_CLASSES[]` | common.sh | 13 KDE system window class names | `is_transient_window` in window.sh |

## 4. Cross-Module Dependencies

```
                        +------------------+
                        |   Core Engine    |
                        | (core.sh)        |
                        +--------+---------+
                                 |
         +-----------+-----------+-----------+-----------+-----------+
         |           |           |           |           |           |
         v           v           v           v           v           v
   +-----------+ +--------+ +----------+ +---------+ +-------+ +-------+
   |  Window   | |Database| |Safe Mode | |Workspace| |  App  | |Screen |
   |Management | |        | |          | |Scripts  | | Defs  | |Detect |
   +-----------+ +--------+ +----------+ +---------+ +-------+ +-------+
```

| Dependency Direction | What Flows | Examples |
|---|---|---|
| Core -> Window Management | Every manipulation call | `move_window_to_desktop`, `move_window_to_screen`, `move_window_to_position`, `get_active_window_uuid`, `close_window`, `raise_window`, `get_window_class`, `get_window_title`, `get_window_pid`, `get_existing_windows_uuid`, `get_uuid_by_process_of_elimination_with_retry`, `wait_for_stable_window` |
| Core -> Database | Window tracking, app metadata | `db_add_window`, `db_claim_window`, `db_delete_window`, `db_get_uuid`, `db_get_all_windows`, `db_delete_stale_windows`, `db_add_existing_windows`, `db_get_app_launch_properties`, `db_get_app_metadata_status`, `db_set_app_class`, `db_set_has_splash_window`, `db_set_post_launch_metadata` |
| Core -> Screen Detection | Geometry for Phase 6 positioning | Screen dimensions, desktop layout |
| Core -> Utils | Debug tracing, validation, display | `debug_function_enter`, `debug_function_exit`, `debug_log`, `info_log`, validators |
| Safe Mode -> Core | Reuses detection functions | `auto_detect_windows`, core detection internals |
| Workspace Scripts -> Core | Generated scripts call core | `execute_launch_window`, `launch_by_app_id` |
| App Definitions -> Core | Launch functions call core | `execute_launch_window` (with app-specific launch_fn) |
| All Modules -> common.sh | Constants | Position, mode, type, timing, path constants |
| All Modules -> error-codes.sh | Error handling | Error code constants, `ERROR_MESSAGES[]` |

## 5. Change Checklist

Use this checklist when modifying any file in the core engine module.

### Changing `execute_launch_window()` (core.sh)

- [ ] Verify parameter count and order -- all 15 parameters must stay in sequence or every caller breaks
- [ ] Check all 7 phases still execute in order
- [ ] Test with all three launch modes: `MULTI`, `SINGLE`, `UNIQUE`
- [ ] Test with both launch types: `TERMINAL` and `DESKTOP`
- [ ] Test with splash window apps and non-splash apps
- [ ] Verify `auto_detect_windows` baseline is still taken before launch
- [ ] Confirm background metadata gathering still runs non-blocking
- [ ] Run workspace open/close test cycle: `kdoitall --verbose --test-open` and `kdoitall --verbose --test-close`
- [ ] Verify generated workspace scripts still function (they hard-code calls to this function)

### Changing `auto_detect_windows()` (core.sh)

- [ ] Test that stale windows are properly cleaned from DB
- [ ] Test that newly appeared windows are properly registered
- [ ] Verify `CURRENT_UUIDS` baseline is correct for subsequent detection
- [ ] Check safe mode functions that depend on this still work

### Changing constants (common.sh)

- [ ] Search entire codebase for the constant name before renaming
- [ ] Check generated workspace scripts -- they embed constant values at generation time
- [ ] If adding positions: update `POSITION_MENU[]`, `POSITION_MENU_ORDER[]`, and `POSITION_ABBREVIATIONS[]`
- [ ] If changing timing constants: test with both fast and slow-launching applications
- [ ] If changing path constants: verify database and workspace script directories still resolve

### Changing error codes (error-codes.sh)

- [ ] Never reuse or renumber existing error codes
- [ ] Add new codes at the end of the appropriate section
- [ ] Always add a corresponding entry in `ERROR_MESSAGES[]`
- [ ] Search for the error code constant name to find all consumers

### General core engine changes

- [ ] Run `kdoitall app validate` to confirm app definitions still load
- [ ] Test with `--verbose` flag to verify debug tracing is intact
- [ ] Check layer ordering in `bin/kdoitall` -- core is Layer 2/3, must not depend on Layer 4+
- [ ] Verify `set -euo pipefail` compatibility -- no unset variables, no unchecked failures
