# Window Detection Pipeline

## Overview

**Problem:** Linux and KDE provide no direct "launch application, receive window ID" API. When an application is launched, the system must determine which of the potentially many on-screen windows belongs to the just-launched app.

**Trigger:** Phase 4 of the `execute_launch_window` pipeline in `lib/core/core.sh`, after an application has been launched and given time to create its window.

**Inputs:**
- Pre-launch window snapshot (CURRENT_UUIDS from Phase 1)
- Pre-launch active window UUID
- Expected window class (may be empty)
- Expected window title pattern (may be empty)
- Launch mode (MULTI, SINGLE, UNIQUE, UNKNOWN)

**Outputs:**
- Detected window UUID
- Detection type: `new_window`, `existing_window`, or `quick_check`
- Splash detection metadata (if applicable): `splash_detected`, `splash_duration_ms`

**Key Files:**
- `lib/window-management/window.sh` -- POE detection, splash handling, class/title search
- `lib/core/core.sh` -- Quick-check logic, detection mode selection, splash auto-learning

---

## Detection Methods

### Method 1: Process of Elimination (POE)

**File:** `lib/window-management/window.sh`

The primary detection method for identifying newly created windows.

**Core function:** `get_uuid_by_process_of_elimination()`

| Step | Action | Detail |
|------|--------|--------|
| 1 | `refresh_current_windows()` | Snapshot all window UUIDs via `kdotool search`. Populates CURRENT_UUIDS[], CURRENT_CLASSES[], CURRENT_TITLES[]. |
| 2 | `db_get_existing_window_uuids()` | Load all tracked UUIDs from the app_windows database table. |
| 3 | Compute set difference | `new = CURRENT_UUIDS - DB_UUIDS - EXCLUDED_UUIDS`. Any UUID present on screen but not in the database and not excluded is a candidate. |
| 4 | Filter transient windows | `is_transient_window()` checks each candidate against the SYSTEM_WINDOW_CLASSES blocklist (e.g., plasma panels, notification widgets, KDE system windows). |
| 5 | Validate candidates | Each remaining candidate must have a non-empty class and a non-empty title. Windows still initializing (empty class/title) are filtered out. |

**Result interpretation:**
- **Single candidate:** Success. Return the UUID.
- **Multiple candidates:** Ambiguous. If a class filter is provided, narrow by class match. If still ambiguous, return the first match (non-deterministic).
- **Zero candidates:** No new window found. Return failure for retry.

**Retry wrapper:** `get_uuid_by_process_of_elimination_with_retry(class, max_wait_ms, retry_interval_ms, initial_exclusions)`

1. Enter polling loop at `retry_interval_ms` intervals (typically 100ms).
2. Each iteration calls the core POE function with a fresh window snapshot.
3. If `class` is provided, filter candidates to those matching the expected class.
4. `initial_exclusions` pre-populates EXCLUDED_UUIDS (used during splash recovery to exclude the dead splash UUID).
5. Loop exits on success or when `max_wait_ms` is exceeded.
6. Default parameters: 5000ms max wait, 100ms retry interval.

### Method 2: Quick-Check

**File:** `lib/core/core.sh` (inline in `execute_launch_window` Phase 4)

Detects when an application reuses or focuses an existing window instead of creating a new one. This is common with single-instance apps like web browsers.

| Step | Action | Detail |
|------|--------|--------|
| 1 | Compare active window | `get_active_window_uuid()` after launch vs. the pre-launch active UUID saved in Phase 3. |
| 2 | Compare window count | Check whether the total number of windows increased. |
| 3 | Evaluate | If active window changed AND window count did NOT increase, the app reused an existing window. |
| 4 | Verify class | If the expected class is known, confirm the new active window's class matches. |

**Result:** Detection type is set to `existing_window` if all conditions hold. The existing window's UUID is used for subsequent phases.

### Method 3: Class/Title Fallback

**File:** `lib/window-management/window.sh` via `get_uuid()`

Last resort when both POE and quick-check fail to identify the window.

| Step | Action | Detail |
|------|--------|--------|
| 1 | Search by class | If class is provided: `kdotool search --class <class>` returns matching window UUIDs. |
| 2 | Search by title | If title_pattern is provided: `kdotool search --name <pattern>` returns matching window UUIDs. |
| 3 | Intersect with known windows | Match results against CURRENT_UUIDS to find valid candidates. |

**Result:** Returns the first matching UUID, or ERR_UUID_NOT_FOUND if no match.

---

## Detection Mode Selection

The order in which methods are tried depends on the application's launch mode:

| Launch Mode | Detection Order | Rationale |
|-------------|----------------|-----------|
| SINGLE_OR_UNIQUE, UNKNOWN | POE -> quick-check -> fallback | For unknown or single-instance apps, POE is the safest first attempt because it makes no assumptions about app behavior. |
| MULTI, UNIQUE | quick-check -> POE -> fallback | For known multi-instance apps, check for window reuse first because these apps commonly focus existing windows instead of creating new ones. |

The rationale is to minimize false positives: POE works best when exactly one new window appears, which is the expected case for unknown apps. Quick-check works best when the app might not create a new window at all, which is common for apps with known multi-instance behavior.

---

## Splash Window Detection

**File:** `lib/window-management/window.sh` via `wait_for_stable_window()`

### Purpose

Some applications (IDEs, office suites, media players) show a splash screen on startup. The splash screen is a separate window with its own UUID. It disappears after loading completes, and the main application window appears. If the splash UUID is returned as the detected window, all subsequent operations (positioning, tracking) will target a window that no longer exists.

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `candidate_uuid` | (required) | The UUID to monitor for stability |
| `max_wait_ms` | 15000 | Maximum monitoring duration |
| `check_interval_ms` | 500 | Polling interval for existence checks |
| `stability_threshold` | 3 | Consecutive alive checks required to declare stability |
| `min_monitor_ms` | 0 | Minimum time to monitor before considering the window stable (used when splash duration is known) |

### Pipeline

**Step 1: Known Splash Delay**
- If `min_monitor_ms > 0` (set when `splash_duration_ms` is known from a previous launch), sleep for that duration first.
- This avoids wasting time monitoring a window that is known to be a splash screen for the first N milliseconds.

**Step 2: Stability Polling**
- Poll `window_exists(candidate_uuid)` at `check_interval_ms` intervals.
- Track a counter of consecutive alive responses.

**Step 3: Stability Declaration**
- When the counter reaches `stability_threshold` (3 consecutive checks), the window is declared stable.
- Return the UUID as the confirmed window.

**Step 4: Grace Period (400ms)**
- If a window disappears during polling, do NOT immediately declare it dead.
- Enter a 400ms grace period and recheck.
- This handles KDE/Wayland compositor transitions where windows may briefly become invisible during desktop effects, workspace switches, or rendering pipeline changes.
- If the window reappears within the grace period, reset the stability counter and continue monitoring.

**Step 5: Splash Death Confirmed**
- If the window remains absent after the grace period, it is confirmed dead (splash lifecycle complete).
- Record `splash_detected = true` and `splash_duration_ms` (elapsed time from monitoring start to death).
- Refresh the database state:
  - `db_get_all_windows()` and `db_delete_stale_windows()` to clean up the dead splash entry.
  - **Empty-snapshot guard:** `refresh_current_windows()` calls `_kdotool_search_safe`, which retries once on empty stdout. If `CURRENT_UUIDS` is *still* empty while `DB_UUIDS` is non-empty after that, both kdotool calls came back empty — likely a sustained kdotool DBus stall. The flow re-polls once more; if still empty, `db_delete_stale_windows()` is skipped to avoid wiping the entire window registry. The next stability iteration will retry from a fresh snapshot.

**Step 6: Search for Replacement**
- Call `get_uuid_by_process_of_elimination_with_retry()` with the dead splash UUID added to the exclusion list.
- This finds the real application window that appeared after the splash died.
- If a replacement is found, continue monitoring it for stability (loop back to Step 2).
- If no replacement is found within `max_wait_ms`, return failure.

**Step 7: Return**
- Return value format: `final_uuid|splash_detected|splash_duration_ms`
- The pipe-delimited format allows the caller to extract all three values.

### Auto-Learning

When `wait_for_stable_window` reports `splash_detected = true`, the calling code in `core.sh` persists this discovery:

1. `db_set_has_splash_window(app_id, "true", splash_duration_ms)` writes to the applications table.
2. On future launches of the same app_id, `execute_launch_window` reads `has_splash_window` and `splash_duration_ms` from the database.
3. The known `splash_duration_ms` is passed as `min_monitor_ms` to `wait_for_stable_window`, causing it to skip the initial monitoring phase and immediately wait past the known splash duration.
4. This makes subsequent launches faster and more reliable.

---

## Module Touchpoints

| Component | File | Key Functions |
|-----------|------|---------------|
| POE Core | lib/window-management/window.sh | `get_uuid_by_process_of_elimination`, `refresh_current_windows`, `is_transient_window` |
| POE Retry | lib/window-management/window.sh | `get_uuid_by_process_of_elimination_with_retry` |
| Quick-Check | lib/core/core.sh | Inline logic in `execute_launch_window` Phase 4 |
| Class/Title Search | lib/window-management/window.sh | `get_uuid`, `get_window_class` |
| Splash Handling | lib/window-management/window.sh | `wait_for_stable_window` |
| DB Sync | lib/db/window-tracking.sh, lib/db/window-info.sh | `db_get_all_windows`, `db_delete_stale_windows`, `db_get_existing_window_uuids` |
| Auto-Learning | lib/core/core.sh, lib/db/app.sh | `db_set_has_splash_window` |
| Transient Filter | lib/window-management/window.sh | `is_transient_window`, SYSTEM_WINDOW_CLASSES |

---

## Edge Cases and Gotchas

1. **Multiple windows appearing simultaneously.** If the launched app opens two windows at once (e.g., a main window and a settings panel), POE will see multiple candidates. If class filtering narrows it to one, that is used. Otherwise the first candidate is selected non-deterministically, and the second window may be orphaned (tracked as auto-detected but not assigned to the workspace).

2. **System notifications mistaken for app windows.** Desktop notifications, panel popups, and other transient windows can appear during the detection window. The SYSTEM_WINDOW_CLASSES blocklist in `is_transient_window` filters these out, but novel transient classes not in the blocklist will be treated as candidates. The blocklist must be maintained as KDE evolves.

3. **Slow application startup.** Apps that take longer than 5 seconds to show a window will exceed the POE retry timeout. The `launch_time_ms` field (populated in Phase 7 metadata) could be used to calibrate the timeout for future launches, but currently the 5-second default is fixed.

4. **Splash windows with identical class to main window.** Some apps use the same window class for both the splash and the main window. POE cannot distinguish them by class. The stability check handles this: the splash UUID dies, and the replacement search finds the main window.

5. **KDE Activities interference.** If the user has KDE Activities enabled and windows move between activities during detection, `kdotool search` may not return windows on inactive activities. This can cause POE to miss the launched window entirely.

6. **Stale CURRENT_UUIDS array.** The `window_exists()` function checks against the CURRENT_UUIDS array, which is only refreshed by explicit calls to `refresh_current_windows()`. Between refreshes, the array can become stale (windows closed or opened without the array knowing). Always call `refresh_current_windows()` before relying on the array contents.

7. **EXCLUDED_UUIDS scope.** The EXCLUDED_UUIDS associative array is reset per detection cycle. It is not persisted between launches. Exclusions from splash recovery only apply within the current `execute_launch_window` invocation.

8. **Electron apps and DevTools.** Electron-based applications (VS Code, Slack, Discord) may open DevTools as a separate window with the same class as the main window. POE will see both as candidates. If DevTools opens during the detection window, it can confuse POE into selecting the wrong window. This is mitigated if the expected window title pattern is provided, allowing title-based disambiguation.

9. **kdotool DBus message delivery race.** kdotool's KWin script emits each window UUID as a separate asynchronous DBus signal (`callDBus("...", "/", "", "result", uuid)`), then exits. kdotool's main thread reads accumulated messages from a background DBus listener immediately after the script returns (`src/main.rs` near line 797), but messages emitted near the end of iteration may still be in flight — the source even carries a `// FIXME: shut down this thread when the script is finished` comment for this exact issue. As a result, each individual `kdotool search` response is a *prefix-subset* of the true window list: the tail can be silently truncated. The race scales with window count (more messages → more likely some are still in flight) and produces two observable failure modes:
   - **Empty stdout** when all messages are still in flight (~1 in 280 polls in steady state)
   - **Partial stdout** missing trailing UUIDs (rate scales with window count)

   **Race-free replacement (snapshot path).** `lib/window-management/snapshot.sh` invokes a custom KWin script (`lib/kwin-scripts/snapshot.js`) that delivers the entire window list as a single batched DBus method call to a session-bus receiver kdoitall registers *before* triggering the script. Both ends are owned, so there is no race window. `refresh_current_windows` uses this path first and falls back to the kdotool defenses below only when snapshot deps are unavailable or KWin scripting fails. Empirical comparison during a digiKam launch (window churn at 100ms polling): snapshot.sh recorded **0 ghost disappearances** vs kdotool's **15** in the same 10-second window. This eliminates the race for `refresh_current_windows`'s call site only — the kdotool defenses listed below remain in service for the other query call sites still on the kdotool path.

   **Architecture.** A long-lived Python daemon (`lib/kwin-scripts/daemon.py`) registers `org.kdoitall.Snapshot` on the session bus and exposes `TakeSnapshot(int timeout_ms) -> string`. The daemon handles the loadScript / start / unloadScript cycle and uses dbus-python's `async_callbacks` to defer the reply to TakeSnapshot until the JS script's `Deliver` call arrives. The bash client (`lib/kwin-scripts/snapshot.sh`) probes for the daemon via qdbus and auto-spawns it (detached via nohup) if absent. Calls are serialized via flock so the daemon never observes concurrent TakeSnapshot requests. Latency: ~18ms median per call once the daemon is warm, ~80ms on cold spawn. The daemon dies cleanly when the session bus closes (logout), or on SIGTERM/SIGINT.

   **Critical detail in the bash spawn**: `nohup ... 200>&-` closes the flock fd in the daemon child. Without it, the daemon inherits fd 200 and holds the lock for its entire lifetime, blocking every subsequent snapshot.sh call.
   
   The race is **not specific to `kdotool search`** — every kdotool query that returns data via `output_result()` is vulnerable: `get_num_desktops`, `getwindowclassname`, `getwindowname`, `getwindowpid`, `getwindowgeometry`, `get_desktop_for_window`, etc. The race manifests anywhere kdoitall reads kdotool's stdout.
   
   Defense layers in kdoitall (each is targeted at a specific call site, not applied globally — the wrapper approach was tried and reverted because it added latency to hot paths and risked emitting phantom UUIDs of just-closed windows). Each protected site uses **up to two 50ms retries on empty stdout**: the first retry catches the common transient (~3% rate becomes ~0%); the second catches longer DBus stalls (~0.37% becomes ~0.01%). Cost only fires when the previous attempt was empty, so the common case is unaffected.
   - **`_kdotool_search_safe`** (`lib/window-management/window.sh`): wraps `kdotool search`. Used by `refresh_current_windows`, `get_existing_windows_uuid`, and `get_uuid`. Addresses the *empty* case at low latency cost. Partial responses are NOT compensated at this layer.
   - **`_kdotool_getactivewindow_safe`**: same retry policy for `kdotool getactivewindow`. Single-UUID query.
   - **Per-window query retry inside `refresh_current_windows`**: each `kdotool getwindowclassname` and `kdotool getwindowname` call (one per UUID in the snapshot) gets the same retry policy before falling back to "N/A". Without this retry, transient empties would corrupt CURRENT_CLASSES/TITLES, breaking class-based matching in POE detection.
   - **`_verify_stale_candidates`** (the key defense at destructive boundaries): before `db_delete_stale_windows` runs, this helper iterates every `DB_UUIDS` entry not present in `CURRENT_UUIDS` and queries kdotool directly with the same retry policy. If the window is alive, it's added back to `CURRENT_UUIDS` to prevent false-positive deletion. Used by `auto_detect_windows` (Phase 1) and the splash-recovery flow in `wait_for_stable_window` (Step 5). Cost scales with the number of stale candidates — typically 0-1 per call.
   - **`get_num_desktops` retry**: `lib/core/screen-detection.sh` uses the same retry policy. Without this, transient empties at startup abort the binary with `ERR_KDOTOOL_DESKTOP_DETECTION_FAILED`.
   - **Empty-snapshot guard in Step 5 above**: final safety net for catastrophic kdotool failure (every query returning empty). Skips cleanup entirely rather than deleting all DB-tracked windows.
   - **POE retry resilience** (no code change needed): `get_uuid_by_process_of_elimination_with_retry` polls every 100ms for up to 5s. A single partial response just means that iteration found no candidate; the next iteration tries again. This retry loop is naturally resilient to transient partials at non-destructive call sites, so we deliberately do NOT add a wrapper there.
   
   The race is an upstream kdotool bug present in v0.2.2 and v0.2.3. Action commands (`windowmove`, `windowactivate`, `set_desktop`, etc.) don't read DBus results back and are not affected. Other one-shot query call sites (e.g., `get_window_pid` in non-blocking metadata gathering) are deliberately left unprotected because they are best-effort paths whose failures are tolerable.
