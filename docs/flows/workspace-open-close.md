# Workspace Open/Close Lifecycle

## Overview

**Trigger:** `kdoitall workspace open <name>` and `kdoitall workspace close <name>` CLI commands.

**Inputs:**
- `workspace_name` -- The name of the workspace to open or close.
- `--skip` flag (open only) -- Bypasses safe mode checks.
- `--verbose` / `--info` flags -- Control debug output level.

**Outputs:**
- **Open:** All workspace windows launched, positioned, and tracked in the database. Workspace marked active.
- **Close:** All workspace windows closed (or released to auto-tracking). Workspace marked inactive.

**Key Files:**
- `lib/commands/workspace/open.sh` -- Open command implementation
- `lib/commands/workspace/close.sh` -- Close command implementation
- `lib/workspace/generator.sh` -- Script generation from workspace definitions
- `~/.local/share/kdoitall/workspaces/<name>.sh` -- Generated workspace scripts

---

## Open Pipeline

### Step 1: Validation

**File:** `lib/commands/workspace/open.sh`

1. Verify `workspace_name` parameter is provided (ERR_MISSING_PARAMETER if not).
2. `db_workspace_exists(workspace_name)` -- Confirm the workspace is defined in the database.
3. Verify the generated script file exists at `WORKSPACE_SCRIPTS_DIR/<name>.sh`.

**Decision point:** If any check fails, abort with an error message.

### Step 2: Save Original Focus

**File:** `lib/commands/workspace/open.sh`

1. `get_active_window_uuid()` captures the user's currently focused window UUID.
2. Store as `saved_active_uuid` for restoration after workspace open completes.

### Step 3: Safe Mode Check

**File:** `lib/commands/workspace/open.sh`, `lib/safe-mode/safe-mode.sh`

Skipped entirely if the `--skip` flag is provided.

1. `detect_safe_mode_apps(workspace_name)` queries for apps in the workspace that have incomplete metadata (unknown class, untested launch behavior, etc.).
2. The check respects `SAFE_MODE_STRICTNESS` configuration:
   - `relaxed` -- Only flags apps with no class and no launch history.
   - `strict` -- Flags apps missing any metadata field.
3. If apps are found, `prompt_safe_mode()` presents an interactive menu:
   - **Accept** -- Run `safe_mode_launch_and_detect()` for each flagged app. This launches the app, detects its window, gathers metadata, then closes it. Results are persisted.
   - **Skip** -- Proceed with workspace open without validation. Apps will be detected at runtime (riskier).
   - **Disable** -- Mark individual apps as validated (bypasses future safe-mode for those apps) or disable safe-mode globally.
   - **Quit** -- Abort the workspace open entirely.

**Decision point:** User choice determines whether the open continues, runs validation first, or aborts.

### Step 4: Source and Execute

**File:** `lib/commands/workspace/open.sh`

1. Source the generated workspace script at `WORKSPACE_SCRIPTS_DIR/<name>.sh`.
2. Call the generated function `open_workspace_<name>()`.
3. Inside the generated function, each window definition calls `execute_launch_window` or a custom launch function from the app definition file.
4. Windows launch **sequentially**, ordered by `display_order` from the `window_definitions` table.
5. Each window goes through the full 7-phase launch pipeline (see `window-launch-pipeline.md`).

### Step 5: Update Metadata

**File:** `lib/commands/workspace/open.sh`

1. `db_mark_workspace_opened()` sets `is_active = TRUE` and `last_opened = NOW()` in the `workspace_definitions` table.

### Step 6: Focus Management

**File:** `lib/commands/workspace/open.sh`

1. Check `db_get_workspace_focus_window(workspace_name)` for a configured default focus window.
2. If a focus window is configured:
   - `db_get_window_uuid_by_name()` retrieves the UUID of that window.
   - `activate_window(uuid)` brings it to the foreground, switching virtual desktop if needed.
3. If no focus window is configured:
   - Restore the original `saved_active_uuid` from Step 2 via `activate_window()`, but only if the window is still alive.

---

## Close Pipeline

### Phase 1: Close Attempt

**File:** `lib/commands/workspace/close.sh`

1. Validate workspace exists and `is_active == TRUE` in the database.
2. `get_active_window_uuid()` to save current focus for restoration.
3. `db_get_workspace_windows_ordered()` retrieves all tracked windows for the workspace, ordered by display_order (reversed for closing).
4. Loop through each window: call `close_window(uuid)` which sends a close request via `kdotool`.
5. Brief sleep to allow windows to process close requests.

### Phase 2: Verification

**File:** `lib/commands/workspace/close.sh`

1. `refresh_current_windows()` updates the live window state from `kdotool`.
2. Loop through each window that was sent a close request:
   - `window_exists(uuid)` checks if the window is still alive.
   - If closed: `db_delete_window(window_name)` removes the tracking entry. Increment closed count.
   - If still alive: add to the stubborn list for Phase 3.

### Phase 3: Assisted Close

**File:** `lib/commands/workspace/close.sh`

For each window that survived Phase 1:

1. `activate_window(uuid)` brings the stubborn window to the user's focus so they can see what is preventing closure (unsaved changes dialog, confirmation prompt, etc.).
2. Poll loop: check `window_not_exists(uuid)` at 1-second intervals up to `CLOSE_WAIT_TIMEOUT`.
3. On timeout, present an interactive prompt:
   - **[s]kip** -- Call `db_release_window_to_auto(window_name)` to move the window to the `~workspace` (auto-tracked pool). The window stays open but is no longer managed by the workspace.
   - **[r]etry** -- Reset the poll loop and try again.
4. Auto-skip triggers after 10 seconds of user inactivity (non-blocking design for unattended operation).

### Phase 4: Cleanup

**File:** `lib/commands/workspace/close.sh`

1. `db_set_workspace_active("FALSE")` marks the workspace as inactive.
2. Restore `saved_active_uuid` focus if the window is still alive.
3. Log summary: N windows closed successfully, M windows skipped/released.

---

## Script Generation Flow

**File:** `lib/workspace/generator.sh`

**Trigger:** Called by `workspace_create`, `workspace_edit`, and `workspace_create_from_file`.

### generate_workspace_script()

1. Reads the workspace definition and window definitions from the database.
2. Generates a standalone bash script containing:
   - Source guard to prevent double-loading.
   - Conditional sourcing of app definition files for each unique app_id in the workspace.
   - An `open_workspace_<name>()` function that calls `execute_launch_window` for each window.
3. Window definitions are encoded in the `WORKSPACE_APPS` array with pipe-delimited format:
   `app_id|window_name|launch_function|desktop|screen|position|parameters`
4. Script is written to `WORKSPACE_SCRIPTS_DIR/<name>.sh`.

### store_window_definitions()

1. `db_delete_window_definitions_for_workspace(workspace_name)` clears existing definitions.
2. For each window in the configuration: `db_add_window_definition()` inserts the new definition.

This is **not transactional** -- a failure mid-way can leave the database in an inconsistent state with partial window definitions.

---

## Module Touchpoints

| Step | Database | Window Mgmt | App Registry | Safe Mode | Screen/Desktop |
|------|----------|-------------|--------------|-----------|----------------|
| Open: Validate | workspace.sh (db_workspace_exists) | -- | -- | -- | -- |
| Open: Save Focus | -- | window.sh (get_active_window_uuid) | -- | -- | -- |
| Open: Safe Mode | app.sh (detect_safe_mode_apps) | window.sh (detect/close) | -- | safe-mode.sh (prompt, launch_and_detect) | -- |
| Open: Execute | window-tracking.sh (add/claim) | all modules (detect/move/position) | app definitions (launch functions) | -- | screen-detection.sh |
| Open: Metadata | workspace.sh (mark_opened) | -- | -- | -- | -- |
| Open: Focus | workspace.sh (focus_window), window-info.sh (uuid_by_name) | window.sh (activate_window) | -- | -- | -- |
| Close: Attempt | window-info.sh (windows_ordered) | window.sh (close_window) | -- | -- | -- |
| Close: Verify | window-tracking.sh (delete_window) | window.sh (window_exists) | -- | -- | -- |
| Close: Assist | window-tracking.sh (release_to_auto) | window.sh (activate_window, window_not_exists) | -- | -- | -- |
| Close: Cleanup | workspace.sh (set_active) | window.sh (activate_window) | -- | -- | -- |

---

## Edge Cases and Gotchas

1. **Missing generated script file.** If `generate_workspace_scripts` failed or was never run, the script file at `WORKSPACE_SCRIPTS_DIR/<name>.sh` will not exist. The open command aborts at Step 1 validation. The fix is to re-run workspace creation or editing.

2. **Safe mode can abort the entire open flow.** If the user selects "Quit" at the safe mode prompt, no windows are launched and the workspace remains inactive. This is intentional but can be surprising in automated workflows.

3. **Sequential window launching.** Windows launch one at a time in display_order sequence. A slow application (e.g., an IDE loading a large project) blocks all subsequent window launches. There is no parallel launch mode.

4. **Assisted close auto-skips after 10 seconds.** In Phase 3, if the user does not respond to the skip/retry prompt within 10 seconds, the system automatically skips the stubborn window. This prevents the close operation from hanging indefinitely but may leave windows open unexpectedly.

5. **Released windows go to the auto-tracked pool.** Windows skipped during close are moved to the `~workspace` with auto-generated names. They are not lost -- they remain tracked -- but they are no longer associated with the original workspace. This can accumulate orphaned entries over time.

6. **Focus restoration may fail.** If the original window (saved in Step 2) was closed during the workspace operation (e.g., it was part of another workspace that got closed), the restoration in Step 6 silently fails and focus remains on the last activated window.

7. **Script generation is not transactional.** `store_window_definitions` deletes all existing definitions before inserting new ones. A crash between the delete and the final insert leaves the workspace with partial window definitions. There is no rollback mechanism.

8. **Generated scripts are not version-locked.** The generated scripts source `lib/core/core.sh` and other library files at runtime. If the library API changes (function signatures, parameter counts), old generated scripts will break. Regeneration is required after library updates.
