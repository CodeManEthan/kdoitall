# Window Management Module — Codebase Impact Map

## 1. Overview

The window management module handles all runtime window operations: detecting windows, reading their properties, manipulating focus and geometry, moving windows across virtual desktops and physical screens, and positioning them according to layout modes. It is the primary interface between the kdoitall automation engine and the KDE desktop environment via `kdotool`.

### Files

| File | Lines | Status |
|------|-------|--------|
| `lib/window-management/window.sh` | 815 | Active — core window detection, property getters, manipulation |
| `lib/window-management/snapshot.sh` | 110 | Active — atomic window-state snapshot via custom KWin script (race-free query path) |
| `lib/window-management/screen.sh` | 705 | Active — physical screen positioning and detection |
| `lib/window-management/desktop.sh` | 136 | Active — virtual desktop operations |
| `lib/window-management/tab.sh` | — | Stub (unused) |
| `lib/kwin-scripts/snapshot.js` | — | KWin script: walks `workspace.windowList()`, delivers JSON via `callDBus` |
| `lib/kwin-scripts/daemon.py` | — | Long-lived session-bus daemon (`org.kdoitall.Snapshot`) exposing `TakeSnapshot(int) -> string`. Handles loadScript+start of the KWin script and async-reply with the delivered payload. |
| `lib/kwin-scripts/snapshot.sh` | — | Thin client: probes for the daemon via qdbus, auto-spawns it via nohup if absent, then calls `TakeSnapshot`. flock-serialized. Returns JSON on stdout. |

---

## 2. Key Files

| File | Purpose |
|------|---------|
| `lib/window-management/window.sh` | Window lifecycle: detection via process-of-elimination, splash window stability checks, property queries (class, title, PID, geometry), focus/close/minimize, global state arrays (CURRENT_UUIDS, CURRENT_CLASSES, CURRENT_TITLES) |
| `lib/window-management/snapshot.sh` | Race-free batch window query: invokes a custom KWin script that returns all windows with class/title/geometry/desktops/output/type-flags atomically. Populates the same CURRENT_UUIDS/CLASSES/TITLES arrays as the kdotool path. Used by `refresh_current_windows` first, with kdotool fallback when deps unavailable. See `docs/flows/window-detection.md` edge case #9 for the race this replaces. |
| `lib/window-management/screen.sh` | Screen-aware positioning: resolves screen references, calculates screen origins, moves windows to screens, positions windows using 24+ layout modes (fullscreen, halves, thirds, quarters, 60/40 splits), detects current window screen and position |
| `lib/window-management/desktop.sh` | Virtual desktop operations: move windows between desktops, get/set current desktop, validate desktop numbers against detected count |
| `lib/window-management/tab.sh` | Stub file — reserved for future browser tab management integration |

---

## 3. Function Impact Map

### Tier 1 — Wide Blast Radius

Changes to these functions risk breaking the core launch engine, workspace commands, window commands, and quick commands simultaneously. Test all downstream callers before modifying.

| Function | File | Description | Approximate Call Sites |
|----------|------|-------------|----------------------|
| `move_window_to_position(uuid, screen_ref, position_mode)` | screen.sh | Calculates relative screen coordinates, moves and sizes window. Handles 24+ position modes (fullscreen, halves, thirds, quarters, 60/40 splits). Calls `resolve_screen_reference()`, `get_screen_info()`, `move_window()`, `size_window()`. | ~10 (core.sh Phase 6, window/move.sh, quick/actions.sh, quick/combo.sh) |
| `activate_window(uuid)` | window.sh | Sets keyboard focus on window. Checks if already active via `get_active_window_uuid()`. Calls `kdotool windowactivate`. | 7+ (core.sh, workspace open/close/focus, window/focus.sh, quick/actions.sh) |
| `close_window(uuid)` | window.sh | Sends close request via `kdotool windowclose`. | 7+ (core.sh execute_close_window, workspace/close.sh, safe-mode.sh) |
| `get_window_class(uuid)` | window.sh | Returns window class string via `kdotool getwindowclassname`. | 8+ (core.sh Phases 3/4/5, safe-mode.sh, POE detection) |
| `window_exists(uuid)` | window.sh | Checks if UUID is present in CURRENT_UUIDS array. | 6+ (workspace close/focus/minimize, window/*.sh, quick/*.sh) |
| `move_window_to_desktop(uuid, desktop)` | desktop.sh | Validates desktop number, calls `kdotool set_desktop_for_window`. | 5 (core.sh Phase 6, window/move.sh, quick/actions.sh, quick/combo.sh) |
| `move_window_to_screen(uuid, screen_ref)` | screen.sh | Resolves screen reference, calculates origin, moves window to top-left of target screen. Calls `resolve_screen_reference()`, `calculate_screen_origin()`, `move_window()`. | 5 (core.sh Phase 6, window/move.sh, quick/actions.sh, quick/combo.sh) |
| `refresh_current_windows()` | window.sh | Populates CURRENT_UUIDS[], CURRENT_CLASSES[], CURRENT_TITLES[]. Tries `snapshot_all_windows()` first (atomic, race-free); falls back to `_kdotool_search_safe` + per-UUID `kdotool getwindowclassname`/`getwindowname` when snapshot deps unavailable or KWin scripting fails. Critical global state refresh. | 4+ (core.sh auto_detect_windows, workspace close/focus/minimize, wait_for_stable_window) |
| `get_uuid_by_process_of_elimination_with_retry(class, max_wait_ms, retry_interval_ms, initial_exclusions)` | window.sh | Retries POE detection until a new window of the expected class appears. Critical path for window launch detection. | 2 (core.sh Phase 4, safe-mode.sh) |
| `wait_for_stable_window(candidate_uuid, max_wait_ms, check_interval_ms, stability_threshold, min_monitor_ms)` | window.sh | Validates window stability with splash detection. Returns `uuid|splash_detected|splash_duration_ms`. Calls `db_get_all_windows`, `db_delete_stale_windows`, `refresh_current_windows`, `get_uuid_by_process_of_elimination_with_retry`. | 2 (core.sh Phase 4b, safe-mode.sh) — critical path for splash detection |

### Tier 2 — Moderate Blast Radius

Changes affect multiple callers but are less pervasive than Tier 1. Test direct callers.

| Function | File | Description | Key Callers |
|----------|------|-------------|-------------|
| `get_active_window_uuid()` | window.sh | Returns focused window UUID via `kdotool getactivewindow`. | activate_window, core.sh, workspace open/close |
| `detect_window_screen(uuid)` | screen.sh | Returns which screen a window is on. | window/move.sh, quick/picker.sh, quick/actions.sh, quick/combo.sh |
| `detect_window_position(uuid, output_num)` | screen.sh | Returns named position or empty string. Uses +/-5px tolerance for matching. | window/move.sh, quick/picker.sh, quick/actions.sh |
| `get_window_title(uuid)` | window.sh | Returns window title via `kdotool getwindowname`. | core.sh, safe-mode.sh, display.sh |
| `get_window_pid(uuid)` | window.sh | Returns PID via `kdotool getwindowpid`. | core.sh, safe-mode.sh |
| `minimize_window(uuid)` | window.sh | Calls `kdotool windowminimize`. | safe-mode.sh, workspace minimize, window minimize commands |
| `validate_desktop_number(desktop)` | desktop.sh | Validates desktop number is within 1..DETECTED_DESKTOP_COUNT. | set_current_desktop, move_window_to_desktop |
| `resolve_position(input)` | screen.sh | Resolves position abbreviations and names to canonical form. | quick/combo.sh |
| `calculate_screen_origin(screen_ref)` | screen.sh | Returns X,Y origin coordinates for a screen. | Internal to screen.sh (move_window_to_screen, move_window_to_position) |
| `validate_screen_number(screen)` / `validate_screen_reference(screen_ref)` | screen.sh | Screen number and reference validation. | Internal to screen.sh functions |

### Tier 3 — Narrow Blast Radius

Internal helpers and rarely-used functions. Changes are generally safe if the immediate caller still works.

| Function | File | Description | Key Callers |
|----------|------|-------------|-------------|
| `snapshot_all_windows()` | snapshot.sh | Atomic, race-free replacement for `_kdotool_search_safe` + per-UUID `getwindowclassname`/`getwindowname` queries. Invokes `lib/kwin-scripts/snapshot.sh`, which calls a long-lived Python daemon (`lib/kwin-scripts/daemon.py`) that drives a custom KWin script and returns all windows in a single batched payload. Populates CURRENT_UUIDS, CURRENT_CLASSES, CURRENT_TITLES from one synchronous call. Returns non-zero when the snapshot tool or its deps are missing so `refresh_current_windows` can fall back to the kdotool path. **~18ms median per call** with daemon already running (vs ~80ms first-call cold-spawn, vs ~205ms for the kdotool-fallback path on 20 windows). The daemon is spawned lazily on first call and lives for the session. | `refresh_current_windows` |
| `snapshot_available()` | snapshot.sh | Cached probe for the snapshot path's dependencies (`python3 + dbus/gobject`, `qdbus-qt6`, an executable `lib/kwin-scripts/snapshot.sh`). First call performs the check; subsequent calls return the cached result. Logs the outcome via `debug_log` so verbose runs surface which path is in use. | `snapshot_all_windows` (internal) |
| `_kdotool_search_safe(args...)` | window.sh | Wraps `kdotool search` with up to two 50ms re-polls on empty stdout. Defends against the *empty* form of an upstream kdotool DBus delivery race (each window UUID is sent as a separate async DBus signal — see `docs/flows/window-detection.md` edge case #9). Two retries cuts the sustained-empty rate from ~0.37% to ~0.01%. Partial responses (non-empty but truncated) are NOT compensated at this layer; `_verify_stale_candidates` is the defense for the destructive-boundary case. Common-case cost: 0ms extra; rare-case cost: 50-100ms. Returns 0 elements only if all 3 calls were empty (suppresses trailing newline so `mapfile -t` produces an empty array, not a single empty element). NOTE: `refresh_current_windows` no longer invokes this on the primary path when `snapshot_all_windows` succeeds, but the wrapper remains in use by `get_existing_windows_uuid` and `get_uuid`. | `refresh_current_windows` (fallback only), `get_existing_windows_uuid`, `get_uuid` |
| `_verify_stale_candidates()` | window.sh | Per-UUID validation before destructive cleanup. For each `DB_UUIDS` entry missing from `CURRENT_UUIDS`, queries `kdotool getwindowclassname` directly with up to two 50ms retries on empty. If the window is alive on any attempt, appends its UUID to `CURRENT_UUIDS` to protect it from `db_delete_stale_windows`. Defends against partial `kdotool search` responses that would otherwise cause false-positive DB deletes. Cost scales with the number of stale candidates (typically 0-1 in steady state). REQUIRES `CURRENT_UUIDS` and `DB_UUIDS` populated. MUTATES `CURRENT_UUIDS`. | `auto_detect_windows` (core.sh Phase 1), `wait_for_stable_window` (splash recovery) |
| `_kdotool_getactivewindow_safe()` | window.sh | Wraps `kdotool getactivewindow` with a single 50ms re-poll on empty result. Single-UUID query, so the prefix-truncation race manifests as either complete or empty rather than partial; one retry is sufficient. Empty active-window results would otherwise corrupt Phase 4 quick-check by silently signaling "desktop focused." | `get_active_window_uuid` |
| `is_transient_window(uuid)` | window.sh | Checks UUID against SYSTEM_WINDOW_CLASSES blocklist. | Internal to POE detection |
| `get_uuid_by_process_of_elimination(class, is_retry)` | window.sh | Single-pass POE scan. | Called only by retry wrapper |
| `get_existing_windows_uuid()` | window.sh | Populates DB_UUIDS from database. | Internal to POE |
| `get_uuid(class, window_title)` | window.sh | Fallback search by class/title via `kdotool`. | core.sh (last resort) |
| `raise_window(uuid)` | window.sh | Brings window to top without changing focus. | Rarely used |
| `move_window(uuid, x, y)` | window.sh | Low-level move via `kdotool windowmove`. | Internal to screen.sh |
| `size_window(uuid, w, h)` | window.sh | Low-level resize via `kdotool windowsize`. | Internal to screen.sh |
| `get_window_size(uuid)` / `get_window_position(uuid)` | window.sh | Geometry queries via `kdotool getwindowgeometry`. | detect_window_screen, detect_window_position |
| `get_process_name(pid)` / `get_executable_path(pid)` | window.sh | PID metadata via `ps` and `/proc`. | safe-mode.sh |
| `window_not_exists(uuid)` | window.sh | Inverse of window_exists. | Close polling loops |
| `get_desktop_for_window(uuid)` / `get_current_desktop()` / `set_current_desktop(desktop)` | desktop.sh | Desktop queries and setter. | Limited callers |

---

## 4. Cross-Module Dependencies

### Modules That Call Into Window Management

| Consumer Module | Files | Functions Used |
|----------------|-------|----------------|
| **Core Engine** | `lib/core/core.sh` | Nearly every Tier 1 function — primary consumer. Drives the full window launch lifecycle (Phases 3-6): detect class, POE detection, stability check, move to desktop, move to screen, position. |
| **Safe Mode** | `lib/app/safe-mode.sh` | `wait_for_stable_window`, `get_uuid_by_process_of_elimination_with_retry`, `close_window`, `get_window_class`, `get_window_title`, `get_window_pid`, `minimize_window` |
| **Workspace Commands** | `lib/commands/workspace/close.sh`, `focus.sh`, `minimize.sh` | `activate_window`, `close_window`, `window_exists`, `refresh_current_windows`, `raise_window`, `minimize_window` |
| **Window Commands** | `lib/commands/window/*.sh` | All manipulation and detection functions (move, focus, close, minimize, screen/position detection) |
| **Quick Commands** | `lib/commands/quick/*.sh` | `detect_window_screen`, `detect_window_position`, `move_window_to_position`, `move_window_to_screen`, `move_window_to_desktop`, `activate_window`, `close_window`, `minimize_window` |

### Modules That Window Management Depends On

| Provider Module | What It Provides |
|----------------|-----------------|
| **Screen Detection** (`lib/core/screen-detection.sh`) | `DETECTED_SCREEN_COUNT`, `SCREEN_OUTPUT_IDS[]`, `SCREEN_INFO[]` — screen geometry data consumed by screen.sh; `resolve_screen_reference()` called by screen.sh |
| **Database** (`lib/core/database.sh`) | `db_get_all_windows`, `db_delete_stale_windows` — called by `wait_for_stable_window` and POE detection |
| **Debug Utilities** (`lib/utils/debug.sh`) | `debug_function_enter`, `debug_function_exit`, `debug_log`, `info_log`, `debug_error` |
| **Error Codes** (`lib/utils/error-codes.sh`) | All ERR_* constants used for structured error reporting |

---

## 5. Global State

| Variable | Type | Managed By | Description |
|----------|------|-----------|-------------|
| `CURRENT_UUIDS[]` | Indexed array | `refresh_current_windows()` | Live window UUIDs from kdotool |
| `CURRENT_CLASSES[]` | Indexed array | `refresh_current_windows()` | Window classes parallel to CURRENT_UUIDS |
| `CURRENT_TITLES[]` | Indexed array | `refresh_current_windows()` | Window titles parallel to CURRENT_UUIDS |
| `EXCLUDED_UUIDS[]` | Associative array | POE detection | UUIDs to skip during process-of-elimination |
| `SYSTEM_WINDOW_CLASSES[]` | Indexed array (13 entries) | window.sh (constant) | Blocklist: plasmashell, kwin, xdg-desktop-portal-kde, etc. |
| `DETECTED_DESKTOP_COUNT` | Integer | screen-detection.sh | Virtual desktop count |
| `DETECTED_SCREEN_COUNT` | Integer | screen-detection.sh | Physical screen count |
| `SCREEN_OUTPUT_IDS[]` | Indexed array | screen-detection.sh | Screen output identifiers |
| `SCREEN_INFO[]` | Associative array | screen-detection.sh | Screen geometry data |

### Timing Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `WINDOW_DELAY` | 0.1s | Delay after window operations |
| `DESKTOP_DELAY` | 0.1s | Delay after desktop operations |
| `SCREEN_DELAY` | 0.1s | Delay after screen operations |
| `POSITION_DELAY` | 0.5s | Delay after positioning operations |

---

## 6. External Tool Dependencies

| Tool | Operations Used |
|------|----------------|
| `kdotool` | `getwindowclassname`, `getwindowname`, `getwindowpid`, `search`, `getwindowgeometry`, `getactivewindow`, `windowactivate`, `windowraise`, `windowmove`, `windowsize`, `windowminimize`, `windowclose`, `get_desktop_for_window`, `get_desktop`, `set_desktop`, `set_desktop_for_window`, `get_num_desktops` |
| `ps` | Process name lookup by PID |
| `readlink` | `/proc/<pid>/exe` resolution |

---

## 7. Error Codes

| Code | Name | Used For |
|------|------|----------|
| 21 | `ERR_UUID_NOT_FOUND` | Window UUID not found in system |
| 24 | `ERR_WINDOW_TITLE_NOT_FOUND` | Could not retrieve window title |
| 25 | `ERR_WINDOW_CLASS_NOT_FOUND` | Could not retrieve window class |
| 26 | `ERR_WINDOW_PID_NOT_FOUND` | Could not retrieve window PID |
| 27 | `ERR_WINDOW_SIZE_NOT_FOUND` | Could not retrieve window size |
| 28 | `ERR_WINDOW_POSITION_NOT_FOUND` | Could not retrieve window position |
| 29 | `ERR_WINDOW_CLASS_MISMATCH` | Window class does not match expected value |
| 10 | `ERR_DESKTOP_NOT_FOUND` | Desktop not found |
| 12 | `ERR_INVALID_DESKTOP_NUMBER` | Desktop number out of valid range |
| 13 | `ERR_DESKTOP_DETECTION_NOT_RUN` | Desktop detection has not been executed |
| 30 | `ERR_SCREEN_VALIDATION_FAILED` | Screen reference validation failed |
| 38 | `ERR_SCREEN_RESOLUTION_FAILED` | Could not resolve screen reference |
| 39 | `ERR_SCREEN_COORDINATES_NOT_FOUND` | Could not determine screen coordinates |
| 51 | `ERR_INVALID_POSITION_MODE` | Unrecognized position mode string |

---

## 8. Change Checklist

Use this checklist when modifying the window management module.

### General

- [ ] Identify which blast radius tier the changed function belongs to
- [ ] Review all call sites listed for the function (use the tier tables above)
- [ ] Verify function signature is unchanged, or update all callers if modified
- [ ] Ensure `debug_function_enter` / `debug_function_exit` tracing is preserved
- [ ] Verify `set -euo pipefail` compliance (all variables quoted, no unset variable access)
- [ ] Check that error codes returned match documented values

### If Modifying Tier 1 Functions

- [ ] Test the full workspace open flow (`kdoitall --verbose --test-open`)
- [ ] Test the full workspace close flow (`kdoitall --verbose --test-close`)
- [ ] Test window commands (`kdoitall window move`, `kdoitall window focus`)
- [ ] Test quick commands (`kdoitall quick` workflows)
- [ ] Verify safe-mode still works if `wait_for_stable_window` or POE functions changed
- [ ] Confirm splash detection pipeline is intact after stability check changes

### If Modifying Global State

- [ ] Verify `refresh_current_windows()` still populates all three parallel arrays correctly
- [ ] Check that EXCLUDED_UUIDS is properly maintained across POE retry cycles
- [ ] Confirm SYSTEM_WINDOW_CLASSES blocklist changes don't exclude legitimate app windows

### If Modifying Screen/Position Logic

- [ ] Test all position modes (fullscreen, halves, thirds, quarters, 60/40 splits)
- [ ] Test on both single-screen and multi-screen configurations
- [ ] Verify the +/-5px tolerance in `detect_window_position` still works
- [ ] Confirm `calculate_screen_origin` returns correct coordinates for all screens

### If Modifying Desktop Logic

- [ ] Test with multiple virtual desktops configured
- [ ] Verify `validate_desktop_number` correctly rejects out-of-range values
- [ ] Confirm desktop detection dependency (`DETECTED_DESKTOP_COUNT`) is checked

### If Adding New Functions

- [ ] Add source guard check at file level if creating a new file
- [ ] Follow existing parameter passing conventions (no globals except constants)
- [ ] Use `local` for all function-scoped variables
- [ ] Add `debug_function_enter` / `debug_function_exit` calls
- [ ] Validate required parameters with `ERR_MISSING_PARAMETER`
- [ ] Document the function in this impact map under the appropriate tier
