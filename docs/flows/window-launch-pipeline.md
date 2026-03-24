# Window Launch Pipeline

## Overview

**Trigger:** Every application launch, invoked by generated workspace scripts or app definition launch functions.

**Entry Point:** `execute_launch_window()` in `lib/core/core.sh`

**Inputs (15 parameters):**
- `workspace_name` -- Name of the workspace this window belongs to
- `window_name` -- Human-readable identifier for this window within the workspace
- `app_id` -- Application registry ID (e.g., `code`, `org.mozilla.firefox`)
- `desktop` -- Target virtual desktop number
- `screen` -- Target screen identifier
- `position` -- Window position constant (e.g., FULLSCREEN, LEFTHALF, TOPRIGHT)
- `launch_mode` -- LAUNCH_MODE_MULTI, LAUNCH_MODE_SINGLE, or LAUNCH_MODE_UNIQUE
- `launch_type` -- LAUNCH_TYPE_DESKTOP or LAUNCH_TYPE_TERMINAL
- `launch_fn` -- The actual launch command or function to execute
- `class` -- Expected window class (may be empty if not yet detected)
- `window_title_pattern` -- Regex or substring to match window title
- `launch_time` -- Expected launch duration in milliseconds (for timeout calibration)
- `launch_fn_arg` -- Additional argument passed to the launch function
- `has_splash_window` -- Whether the app is known to show a splash screen ("true"/"false"/"unknown")
- `splash_duration_ms` -- Known splash screen duration in milliseconds (0 if unknown)

**Outputs:**
- Window tracked in `app_windows` table with UUID
- Window positioned on target desktop/screen/position
- Application metadata updated (class, splash info, launch timing)

---

## Step-by-Step Pipeline

### Phase 1: Pre-Launch Snapshot

**File:** `lib/core/core.sh`

1. Call `auto_detect_windows()` to establish a baseline of all currently visible windows.
2. Internally this calls `refresh_current_windows()` which populates the global arrays `CURRENT_UUIDS[]`, `CURRENT_CLASSES[]`, and `CURRENT_TITLES[]` by querying `kdotool`.
3. Sync the database with reality:
   - `db_get_all_windows()` retrieves all tracked windows from the database.
   - `db_delete_stale_windows()` removes database entries for windows that no longer exist on screen.
   - `db_add_existing_windows()` registers any on-screen windows not yet in the database (discovered externally).

**Decision point:** None -- this phase always runs.

### Phase 2: Single-Instance Short Circuit

**File:** `lib/core/core.sh`

1. Check if `launch_mode == LAUNCH_MODE_SINGLE`.
2. If yes, search existing tracked windows for one with a matching class.
3. If a match is found:
   - Call `db_claim_window()` to reassign the existing window to the current workspace/window_name.
   - Call `raise_window()` to bring it to the foreground.
   - Call `get_window_title()` for metadata.
   - **Skip directly to Phase 6** (positioning).
4. If no match, continue to Phase 3.

**Decision point:** Does a window with the expected class already exist in the database?

### Phase 3: Prepare and Launch

**File:** `lib/core/core.sh`

1. Record pre-launch state:
   - `get_active_window_uuid()` captures the currently focused window.
   - Count existing windows in `CURRENT_UUIDS[]`.
   - Record timestamp for launch timing measurement.
2. Execute `$launch_fn` -- the actual launch command.
   - For `LAUNCH_TYPE_DESKTOP`: calls `_launch_via_gtk` which uses `gtk-launch`.
   - For `LAUNCH_TYPE_TERMINAL`: runs the custom shell command from the app definition.
3. Sleep `LAUNCH_DELAY` (1.0s default) to give the window time to appear.

### Phase 4: Detect Window

**File:** `lib/core/core.sh`

Detection ordering depends on launch mode:

| Launch Mode | Order |
|-------------|-------|
| SINGLE_OR_UNIQUE, UNKNOWN | POE first (5s, 100ms intervals) -> quick-check -> class/title fallback |
| MULTI, UNIQUE | quick-check first -> POE (5s) -> class/title fallback |

**POE (Process of Elimination):**
- `get_uuid_by_process_of_elimination_with_retry()` compares the current window list against the Phase 1 snapshot.
- New windows = current windows minus pre-launch windows minus excluded UUIDs.
- Polls at 100ms intervals up to 5s total.

**Quick-Check:**
- Compares `get_active_window_uuid()` after launch with the pre-launch active UUID.
- If the active window changed but the total window count did not increase, the app reused an existing window.
- Verifies class match if class is known.

**Class/Title Fallback:**
- `get_uuid(class, title_pattern)` uses `kdotool search` to find windows by class or title.
- Last resort when POE and quick-check both fail.

**Detection result** is tagged as one of: `new_window`, `existing_window`, or `quick_check`.

### Phase 4b: Splash Stability Check

**File:** `lib/core/core.sh`

1. If a window was detected, call `wait_for_stable_window()`.
2. If `has_splash_window` is known and `splash_duration_ms > 0`: set `min_monitor_ms` to skip past the known splash phase.
3. Monitor window existence at regular intervals:
   - Requires 3 consecutive alive checks to declare stability.
   - 400ms grace period handles brief KDE compositor transitions where the window momentarily disappears.
4. If the window dies (splash lifecycle detected):
   - Record `splash_detected = true` and `splash_duration_ms`.
   - Refresh database state via `db_get_all_windows()` and `db_delete_stale_windows()`.
   - Search for replacement window via POE retry with the dead UUID added to exclusions.
   - Continue monitoring the replacement for stability.
5. If splash was auto-detected, call `db_set_has_splash_window()` to persist the discovery.
6. Return value: `final_uuid|splash_detected|splash_duration_ms`.

### Phase 5: Register Window

**File:** `lib/core/core.sh`

**For `new_window` detection:**
1. If the app's class is not yet known, call `detect_and_store_class()`:
   - `get_window_class(uuid)` queries the window manager.
   - `db_set_app_class(app_id, class)` persists the discovered class.
2. Call `db_add_window()` to register the window in the `app_windows` table with its UUID, workspace, and window name.

**For `existing_window` or `quick_check` detection:**
1. Call `raise_window()` to ensure visibility.
2. Call `db_claim_window()` to reassign the existing window to the current workspace.

### Phase 6: Position Window

**File:** `lib/core/core.sh`, calling into window management modules

1. `move_window_to_desktop(uuid, desktop)` -- Uses `kdotool set_desktop_for_window` to move the window to the target virtual desktop.
2. `move_window_to_screen(uuid, screen)` -- Resolves the screen name to physical coordinates, calculates the screen origin, and moves the window.
3. `move_window_to_position(uuid, screen, position)` -- Calculates pixel coordinates relative to the target screen and applies position + size via `kdotool`.

### Phase 7: Background Metadata Gathering

**File:** `lib/core/core.sh`

1. Call `gather_post_launch_metadata()` -- non-blocking data collection.
2. `db_get_app_metadata_status()` checks which metadata fields are already populated.
3. For missing fields, gather:
   - **PID validation:** `get_window_pid()` -> `get_process_name()` -> `get_executable_path()`.
   - **Title pattern:** `get_window_title()` -> `auto_select_title_pattern()`.
   - **Launch timing:** Calculate elapsed time from Phase 3 timestamp. Apply rolling average (50% buffer on first sample, 25% buffer on subsequent samples).
4. `db_set_post_launch_metadata()` performs a conditional write, only updating fields that are currently NULL/empty.

---

## Module Touchpoints

| Phase | Database | Window Management | App Definitions | Screen/Desktop |
|-------|----------|-------------------|-----------------|----------------|
| 1: Pre-Launch Snapshot | db_get_all_windows, db_delete_stale_windows, db_add_existing_windows | refresh_current_windows (kdotool) | -- | -- |
| 2: Single Short Circuit | db_claim_window | get_window_title, raise_window | -- | -- |
| 3: Prepare & Launch | -- | get_active_window_uuid | launch function (app .sh) | -- |
| 4: Detect Window | -- | get_uuid_by_process_of_elimination_with_retry, get_active_window_uuid, get_existing_windows_uuid, get_window_class, get_uuid | -- | -- |
| 4b: Splash Check | db_set_has_splash_window, db_get_all_windows, db_delete_stale_windows | wait_for_stable_window | -- | -- |
| 5: Register Window | db_add_window or db_claim_window, db_set_app_class | get_window_class, raise_window, get_window_title | -- | -- |
| 6: Position Window | -- | move_window_to_desktop, move_window_to_screen, move_window_to_position | -- | desktop.sh, screen.sh, screen-detection.sh |
| 7: Metadata | db_get_app_metadata_status, db_set_post_launch_metadata | get_window_pid, get_process_name, get_executable_path, get_window_title | auto_select_title_pattern | -- |

---

## Edge Cases and Gotchas

1. **Splash windows die and get replaced.** The stability check detects this and retries POE with the dead splash UUID in the exclusion list. If the replacement also dies (nested splash), detection may fail.

2. **KDE compositor transitions.** Wayland compositors may briefly hide windows during desktop effects. The 400ms grace period in `wait_for_stable_window` prevents false splash detection during these transitions.

3. **Electron apps share PIDs.** Multiple Electron windows (VS Code, Slack, etc.) share a single process. Launch mode detection and PID-based metadata must account for this; PID alone cannot distinguish windows.

4. **LAUNCH_MODE_SINGLE can claim the wrong window.** If two different apps happen to register the same window class, the Phase 2 short circuit may grab an unrelated window. Class accuracy in the database is critical.

5. **gtk-launch may not create a new window.** If the app is already running, `gtk-launch` may simply focus the existing window instead of spawning a new one. The quick-check detection method handles this case.

6. **Launch timing includes stability check time.** The measured launch duration includes the time spent in Phase 4b, making it an overestimate. Future launches use this inflated value for timeout calibration, which is conservative but safe.

7. **Auto-learned splash status persists.** Once `db_set_has_splash_window` is called, all future launches of that app use the known splash duration to set `min_monitor_ms`. Incorrect auto-detection is sticky.

8. **Phase 7 metadata is non-blocking.** Failures in metadata gathering (e.g., PID not available, title pattern extraction fails) do not affect the launch outcome. The window is already positioned and tracked. Missing metadata will be retried on subsequent launches.
