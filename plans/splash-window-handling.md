# Splash Window Handling — Investigation & Implementation Plan

## Problem Summary

Applications like digiKam create transient windows (splash screens, dialogs, loading
screens) before their actual main window appears. The current detection logic grabs the
first new UUID and declares victory, leading to:

1. Incorrect launch time measurement (measuring splash appearance, not app readiness)
2. Metadata gathered from wrong window (splash may have different title/properties)
3. `close_window` targeting a UUID that no longer exists, leaving the real window open
4. In execute_launch_window: positioning a splash/dialog instead of the real window

### Observed digiKam Window Lifecycle

```
Phase 1: Dialog window — UUID 730cda35, class org.kde.digikam, title "Collection not Found — digiKam"
Phase 2: UUID 730cda35 disappears, tiny transient b01e4ece appears briefly (empty class, 43x26)
Phase 3: Intermediate window UUID 7d7ed8d8, class org.kde.digikam, title "digiKam" — then degrades/dies
Phase 4: Final window UUID 57437770, class org.kde.digikam, title "digiKam" — stable
Also:    Helper widget UUID 77c76fd9, class "digikam" (lowercase), empty title, 63x27
         Plasmashell notification 807c8a27, class org.kde.plasmashell, 332x90
```

Key observations:
- Three distinct UUIDs before the final stable window
- Helper widget has a DIFFERENT class name (lowercase "digikam" vs "org.kde.digikam")  
- Transient windows have tiny sizes and/or empty class/title
- The final window keeps the same class as the initial dialog

---

## Part 1: Transient Window Filtering in get_uuid_by_process_of_elimination

### Problem
`get_uuid_by_process_of_elimination` can detect transient system windows (notifications,
tooltips, tray widgets) as the "new" window. The status command already filters these
in `db_get_untracked_windows` via a class blocklist, but that filtering doesn't apply
during launch detection.

### Proposed Solution
Add a validation step inside `get_uuid_by_process_of_elimination` that rejects windows
matching transient/system window characteristics. A window should be rejected if ANY of:

1. **Blocklisted class** — matches the same list used in `db_get_untracked_windows`:
   `plasmashell`, `kwin_wayland`, `kwin_x11`, `kwin`, `xdg-desktop-portal-kde`,
   `org.kde.kscreen.osd`, `kded5`, `kded6`, `polkit-kde-authentication-agent-1`,
   `ksplashqml`, `ksmserver`, `org.kde.plasmashell`, `xwaylandvideobridge`

2. **Empty class AND empty title** — window hasn't been initialized yet, or is a
   tooltip/helper artifact

3. **Tiny window with empty title** — heuristic: geometry below a minimum threshold
   (e.g., width < 100 AND height < 100) combined with an empty or missing title.
   This catches tray icons and tooltip-like windows (the 43x26 and 63x27 windows
   in the digiKam trace).

### Implementation Location
- New helper function `is_transient_window()` in `lib/window-management/window.sh`
- Called from `get_uuid_by_process_of_elimination` after finding a new UUID candidate,
  before accepting it
- If transient → add to EXCLUDED_UUIDS and continue retrying (same pattern as
  class-mismatch rejection)

### is_transient_window Logic
```
is_transient_window(uuid):
    class = get class for uuid (from kdotool, not DB)
    title = get title for uuid
    
    if class is in SYSTEM_WINDOW_CLASSES blocklist → return 0 (transient)
    if class is empty AND title is empty → return 0 (transient)
    if (width < 100 AND height < 100) AND title is empty → return 0 (transient)
    
    return 1 (not transient)
```

### Shared Blocklist
Extract the system window class list into a global constant array
(e.g., `SYSTEM_WINDOW_CLASSES`) defined in `lib/core/common.sh` or similar, so both
`is_transient_window` and `db_get_untracked_windows` reference the same list. The SQL
query in `db_get_untracked_windows` would need to be refactored to use this shared list
(or remain hardcoded with a comment noting the duplication — simpler approach).

**Decision needed:** Shared constant vs. accept the duplication with a comment?

---

## Part 2: New Metadata — `has_splash_window`

### Column Definition
A boolean flag indicating that this application creates one or more transient windows
before its final main window appears during launch.

**Add to both tables:**

`applications` table:
```sql
ALTER TABLE applications ADD COLUMN has_splash_window BOOLEAN DEFAULT FALSE;
```

`app_registry` table:
```sql
ALTER TABLE app_registry ADD COLUMN has_splash_window BOOLEAN DEFAULT 0;
```

### What This Flag Means
When `has_splash_window = TRUE`:
- Safe mode detected that the initially appeared window was replaced by a different UUID
- The application's launch involves a multi-phase window lifecycle
- Detection logic should wait for window stabilization rather than accepting the first UUID

### Where It Gets Set
- **Safe mode** — automatically detected during `safe_mode_measure_launch_time` (Part 3)
- **App registry** — pre-populated for known applications (manual curation)
- **Never set by `gather_post_launch_metadata`** — this is safe-mode-only detection to
  avoid the overhead during normal launches

### Where It Gets Read
- `db_get_app_launch_properties` — needs to include `has_splash_window` in its SELECT
- `execute_launch_window` — uses it to choose detection strategy (Part 4)
- `app_registry_get_metadata` — include in registry lookups

---

## Part 3: Safe Mode — Splash Window Detection

### Current Flow (safe_mode_measure_launch_time)
```
1. auto_detect_windows (snapshot)
2. gtk-launch app_id
3. get_uuid_by_process_of_elimination_with_retry("", 30000, 100) → first new UUID
4. minimize_window(uuid)
5. Store launch time, return UUID
```

### Problem
Step 3 returns the first UUID that passes transient filtering, which may be a splash or
dialog window, not the final application window.

### Proposed Solution — Window Stability Verification
After detecting the first UUID, add a stability verification phase that monitors whether
the UUID survives for a stabilization period. If it disappears, re-scan for its
replacement.

**New flow for safe_mode_measure_launch_time:**
```
1. auto_detect_windows (snapshot)  
2. gtk-launch app_id
3. get_uuid_by_process_of_elimination_with_retry("", 30000, 100) → candidate UUID
4. Record initial_launch_time (time to first window)
5. STABILITY CHECK: wait_for_stable_window(candidate_uuid, stabilization_timeout)
   - Every 500ms for up to 15 seconds:
     a. Check if candidate UUID still exists (kdotool getwindowclassname)
     b. If it exists with valid class/title → increment stability counter
     c. If stability counter reaches threshold (e.g., 3 consecutive checks = 1.5s stable) → accept
     d. If UUID disappears:
        - Set splash_detected = true
        - Re-run get_uuid_by_process_of_elimination_with_retry with remaining timeout
        - If new UUID found → restart stability check with new UUID
        - If no new UUID found within timeout → fail
6. If splash_detected: store has_splash_window = TRUE for this app_id
7. minimize_window(final_stable_uuid)
8. Record final_launch_time (time to stable window)
9. Return final_stable_uuid
```

### New Function: wait_for_stable_window
Location: `lib/window-management/window.sh`

Parameters:
- `candidate_uuid` — the UUID to monitor
- `max_wait_ms` — total time budget for stabilization (default: 15000)
- `check_interval_ms` — how often to check (default: 500)
- `stability_threshold` — consecutive successful checks needed (default: 3)

Returns (pipe-separated):
- `final_uuid` — the stabilized UUID (may differ from input if replacement occurred)
- `splash_detected` — "true" or "false"

### Impact on Launch Time Measurement
With splash detection, we get two timing measurements:
- `initial_launch_time` — time to first window (useful for timeout calculations)
- `stable_launch_time` — time to final stable window (the real app readiness time)

For `has_splash_window` apps, `launch_time_ms` in the database should store the
`stable_launch_time` since that's what execute_launch_window needs for its retry timeout.

### Safe Mode Summary Display
Update `safe_mode_display_summary_and_confirm` to show splash window detection:
```
  Splash Window: Yes (initial window replaced after ~3.2s)
```

---

## Part 4: execute_launch_window — Known Splash Behavior

### Current Flow (Phase 4: Detect Window)
The function uses `get_uuid_by_process_of_elimination_with_retry` with a 5000ms timeout
and accepts the first UUID found.

### Changes When has_splash_window = TRUE

When we know an app has splash behavior, modify Phase 4 to use the stability check
after initial detection:

```
Phase 4 changes:

if has_splash_window == TRUE:
    # Detect initial window with short timeout
    uuid = get_uuid_by_process_of_elimination_with_retry(class, launch_time, 100)
    
    if uuid found:
        # Wait for stability — the initial UUID may be replaced
        stable_result = wait_for_stable_window(uuid, launch_time * 2, 500, 3)
        final_uuid = parse final_uuid from stable_result
        
        if final_uuid != uuid:
            # UUID was replaced — re-sync DB before registering
            auto_detect_windows
        
        uuid = final_uuid
else:
    # Current behavior (unchanged)
    uuid = get_uuid_by_process_of_elimination_with_retry(class, 5000, 100)
```

### Parameter Changes
`db_get_app_launch_properties` needs to return `has_splash_window` as an additional field.
`launch_by_app_id` needs to pass it through to `execute_launch_window` as a new parameter.
`execute_launch_window` signature adds parameter `${14}` for `has_splash_window`.

---

## Part 5: execute_launch_window — Unknown Splash Behavior

### Problem
When `has_splash_window` is empty/unknown (app hasn't been through safe mode, not in
registry), we don't want to add latency to every launch by doing full stability checks.

### Proposed Approach — Lightweight Verification
After detecting a UUID via process-of-elimination, do a single quick verification:

```
# After uuid is detected via process of elimination:
if has_splash_window is unknown/empty AND detection_method == "new_window":
    # Quick sanity check: does the UUID still exist after a brief pause?
    sleep 1
    if window_not_exists(uuid):
        # UUID disappeared — likely a splash window
        # Re-scan with extended timeout
        auto_detect_windows
        uuid = get_uuid_by_process_of_elimination_with_retry(class, 10000, 200)
        
        if uuid found:
            # Record this finding for future launches
            # (handled by gather_post_launch_metadata or a new flag)
```

This adds only 1 second of latency for unknown apps (acceptable) and self-corrects
when it detects a disappearing UUID. For apps that DON'T have splash windows, the
1-second check passes immediately and continues normally.

### Automatic Learning
If the quick verification detects a splash pattern (UUID disappeared), the
`gather_post_launch_metadata` function could set `has_splash_window = TRUE` so future
launches use the full stability check from Part 4. This makes the system self-improving.

**Decision needed:** Should we auto-set `has_splash_window` from execute_launch_window,
or only from safe mode? Auto-setting is convenient but could produce false positives
if a window closed for other reasons.

---

## Implementation Order

1. **Part 1 first** — Transient window filtering. Low risk, high value, standalone.
2. **Part 2 next** — Schema changes. Foundation for Parts 3-5.
3. **Part 3** — Safe mode stability detection. Most thorough testing ground.
4. **Part 4** — execute_launch_window with known splash.
5. **Part 5** — execute_launch_window with unknown splash.

---

## Open Questions

1. **Shared blocklist vs. duplication** — Should `SYSTEM_WINDOW_CLASSES` be a shared
   constant, or keep the SQL blocklist separate from the bash array?

2. **Auto-learning in execute_launch_window** — Should Part 5's quick-check auto-set
   `has_splash_window`, or leave that exclusively to safe mode?

3. **Stability check parameters** — Are 500ms interval / 3 consecutive checks / 15s max
   reasonable defaults for safe mode? Should execute_launch_window use tighter params?

4. **Launch time storage for splash apps** — Store only stable_launch_time, or both
   initial and stable times?
