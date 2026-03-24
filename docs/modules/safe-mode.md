# Safe Mode Module — Codebase Impact Map

## Overview

Safe mode is an interactive validation system for application metadata that cannot be determined statically. When an application is first used in a workspace, safe mode launches it in isolation and runs a multi-stage detection pipeline: measure launch time, detect window class, test PID validation reliability, identify title patterns, determine instance support (single vs multi), and detect splash windows. All results are stored in the `applications` table for future launches, ensuring reliable window detection and management without repeated user intervention.

## Key Files

| File | Role |
|------|------|
| `lib/app/safe-mode.sh` | Core safe-mode validation logic (12 functions, ~1002 lines) |
| `lib/commands/app/safe-mode.sh` | Safe-mode command handler (skip, reset, interactive menu) |

## Function Impact Map

### Tier 1 — High Impact (breaking changes ripple widely)

#### `safe_mode_launch_and_detect(app_id)` — safe-mode.sh
- Multi-stage interactive validation pipeline:
  1. Measure launch time
  2. Detect window class
  3. Auto-detect PID validation reliability
  4. Auto-detect title pattern
  5. Auto-detect launch mode (single/multi)
  6. Display summary for user confirmation
  7. Store results to database
- **Database reads:** `db_get_display_name`
- **Database writes:** `db_set_safe_mode_results`
- **Window operations:** `get_window_class`, `close_window`
- **Returns:** UUID on success
- **Callers:** `workspace_open` (lib/commands/workspace/open.sh), `app_safe_mode` (interactive command)
- **Impact:** Gateway for all new application validation. Changes here affect workspace launch reliability for every application that hasn't been validated yet.

#### `detect_safe_mode_apps(workspace_name)` — safe-mode.sh
- Queries which applications in a workspace still need validation.
- Behavior controlled by `SAFE_MODE_STRICTNESS` config (relaxed|strict).
- **Database:** `db_get_apps_needing_safe_mode`, `db_mark_apps_requiring_safe_mode`
- **Callers:** `workspace_open` (runs before launching any windows)
- **Impact:** Determines whether a workspace open is interrupted by safe mode prompts. Strictness changes alter which fields are considered required.

#### `prompt_safe_mode(app_ids...)` — safe-mode.sh
- User interaction flow: presents pending apps list with options [A]ccept, [S]kip, [D]isable, [Q]uit.
- Calls `prompt_safe_mode_disable_menu` for the disable sub-flow.
- **Callers:** `workspace_open`
- **Impact:** Controls the user-facing safe mode experience. Changes to prompt flow affect workspace open UX.

### Tier 2 — Medium Impact (used by multiple consumers or contain significant logic)

#### `safe_mode_measure_launch_time(app_id)` — safe-mode.sh
- Launches the application and measures startup duration.
- Detects splash windows via `wait_for_stable_window`.
- **Database:** `db_set_launch_time`
- **Window operations:** `auto_detect_windows`, `get_uuid_by_process_of_elimination_with_retry` (30s timeout), `wait_for_stable_window`, `minimize_window`
- **Returns:** `uuid|splash_detected|splash_duration_ms`
- **Impact:** Launch time measurement feeds into launch mode detection timeout calculation.

#### `safe_mode_auto_detect_launch_mode(app_id, existing_uuid, class, launch_time_ms, splash_detected, splash_duration_ms)` — safe-mode.sh
- Launches a second instance via `gtk-launch` to determine if the app supports multiple windows.
- Checks for shared PID (Electron app detection).
- Timeout: 1.5x first launch time (minimum 3s).
- **Returns:** `mode|pid_override`
- **Impact:** Determines LAUNCH_MODE_SINGLE vs LAUNCH_MODE_MULTI vs LAUNCH_MODE_UNIQUE for the app.

#### `safe_mode_auto_detect_pid(app_id, uuid)` — safe-mode.sh
- Tests whether PID-based window identification is reliable for this application.
- Uses `get_window_pid`, `get_process_name`, `get_executable_path`.
- **Returns:** `true|process_name|exe_path` or `false||`
- **Impact:** Affects whether the system can use PID matching for window identification during normal operations.

#### `safe_mode_auto_detect_title_pattern(app_id, uuid, display_name, class)` — safe-mode.sh
- Parses window title into segments and selects the best match for identification.
- Prefers segments matching display_name or class; falls back to rightmost segment.
- **Impact:** Title patterns are used for window identification during workspace operations.

#### `safe_mode_display_summary_and_confirm(...)` — safe-mode.sh
- Shows detected metadata summary with options: [Y]es (accept), [R]etry, [T]itle edit, [S]kip.
- **Impact:** User confirmation gate before metadata is persisted.

#### `safe_mode_manual_title_pattern_selection(uuid, current_title)` — safe-mode.sh
- Interactive UI for manual title pattern choice from parsed title segments.
- Triggered by [T]itle edit in the summary confirmation.

#### `prompt_safe_mode_disable_menu(apps_array_ref)` — safe-mode.sh
- Sub-menu for disabling safe mode: [D]isable globally, [A]ll listed apps, [1-n] specific app, [B]ack.
- **Database:** `db_set_safe_mode_completed`
- **Impact:** Allows users to bypass safe mode per-app or globally.

#### `app_safe_mode(subcommand, app_id)` — commands/app/safe-mode.sh
- Command handler for `kdoitall app safe-mode`.
- Subcommands: `skip` (mark validated without running), `reset` (clear metadata), interactive menu.
- **Database:** `db_application_exists`, `db_set_safe_mode_completed`, `db_clear_safe_mode_data`, `db_count_pending_safe_mode_apps`, `db_get_pending_safe_mode_apps`

### Tier 3 — Low Impact (internal helpers, rarely changed)

- `safe_mode_disable_globally()` — Writes `SAFE_MODE_PROMPTING="disabled"` to `KDOITALL_CONFIG` file.
- `safe_mode_store_metadata(app_id, uuid)` — Legacy function, mostly superseded by `db_set_safe_mode_results`.

## Configuration Variables

| Variable | Values | Effect |
|----------|--------|--------|
| `SAFE_MODE_STRICTNESS` | `relaxed` / `strict` | Controls how many missing database fields trigger safe mode for an app |
| `SAFE_MODE_PROMPTING` | `enabled` / `disabled` | Global enable/disable for safe mode prompts |

## Database Columns Written

Safe mode writes the following columns in the `applications` table:

| Column | Set By | Purpose |
|--------|--------|---------|
| `app_class` | launch_and_detect | Window class for identification |
| `supports_pid_validation` | auto_detect_pid | Whether PID matching is reliable |
| `process_name` | auto_detect_pid | Process name for PID matching |
| `executable_path` | auto_detect_pid | Binary path for PID matching |
| `window_title_pattern` | auto_detect_title_pattern | Title segment for window matching |
| `launch_mode` | auto_detect_launch_mode | SINGLE / MULTI / UNIQUE |
| `has_splash_window` | measure_launch_time | "true" / "false" / "unknown" |
| `splash_duration_ms` | measure_launch_time | Splash screen duration in ms |
| `launch_time_ms` | measure_launch_time | Startup time measurement |
| `launch_time_samples` | measure_launch_time | Number of measurements taken |
| `safe_mode_completed` | prompt / command | Whether validation is done |
| `requires_safe_mode` | detect_safe_mode_apps | Whether app needs validation |

## Cross-Module Dependencies

| Module | Dependency Direction | Details |
|--------|---------------------|---------|
| **Core Engine** | safe-mode --> core | `auto_detect_windows`, `get_uuid_by_process_of_elimination_with_retry`, `wait_for_stable_window` |
| **Window Management** | safe-mode --> window | `get_window_class`, `get_window_title`, `get_window_pid`, `close_window`, `minimize_window`, `get_process_name`, `get_executable_path` |
| **Database** (lib/db/app.sh) | safe-mode --> db | Extensive usage — launch properties, safe mode flags, metadata reads/writes |
| **Workspace Open** | workspace --> safe-mode | Primary integration point — safe mode runs before workspace launch begins |
| **Display** | safe-mode --> display | `parse_window_title_segments`, `display_application_info` |
| **Config** | safe-mode --> config | Reads/writes `KDOITALL_CONFIG` file for global disable |

## Change Checklist

When modifying this module, verify the following:

- [ ] **Changing `safe_mode_launch_and_detect()` pipeline stages?** Ensure the return value contract (UUID on success) is maintained — `workspace_open` depends on it.
- [ ] **Changing `detect_safe_mode_apps()` query logic?** Test with both `SAFE_MODE_STRICTNESS=relaxed` and `SAFE_MODE_STRICTNESS=strict` to ensure correct app filtering.
- [ ] **Changing prompt flow in `prompt_safe_mode()`?** Verify [A]ccept, [S]kip, [D]isable, [Q]uit all work and that workspace open handles each outcome correctly.
- [ ] **Changing launch time measurement?** The timeout for `safe_mode_auto_detect_launch_mode` is calculated as 1.5x the measured launch time (3s minimum) — ensure this relationship is preserved.
- [ ] **Changing title pattern detection?** Test with apps that have multi-segment titles (e.g., "filename - Application Name") and apps with minimal titles.
- [ ] **Changing launch mode detection?** Test with single-instance apps (e.g., system settings), multi-instance apps (e.g., terminal), and Electron apps (shared PID).
- [ ] **Changing splash window detection?** Verify `wait_for_stable_window` integration and that `has_splash_window` / `splash_duration_ms` are written correctly.
- [ ] **Changing database columns written?** Update `db_set_safe_mode_results` and `db_clear_safe_mode_data` to stay in sync.
- [ ] **Changing `app_safe_mode` command?** Test `skip`, `reset`, and interactive menu paths.
- [ ] **Adding new metadata fields?** Update the summary display, database write functions, and the `SAFE_MODE_STRICTNESS` field checks.
- [ ] **Test with `--verbose`** to confirm debug output traces through all detection stages correctly.
