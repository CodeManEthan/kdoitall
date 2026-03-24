# Application Discovery Pipeline

## Overview

**Trigger:** `kdoitall app scan` CLI command.

**Entry Point:** `registry_scan_applications()` in `lib/app/registry.sh`

**Inputs:**
- System `.desktop` files from standard XDG directories.
- App definition files in `lib/app-definitions/apps/<app_id>/` (metadata.json, functions.sh).
- Reference registry database (read-only, ships with the tool).

**Outputs:**
- `applications` table populated/updated with discovered apps.
- `launch_options` and `launch_parameters` tables populated for apps with terminal launch support.
- Uninstalled applications removed from the database.

---

## Step-by-Step Pipeline

### Step 1: Iterate Desktop File Locations

**File:** `lib/app/registry.sh`

Process the `DESKTOP_FILE_LOCATIONS[]` array in order:
1. `/usr/local/share/applications/`
2. `/usr/share/applications/`
3. `~/.local/share/applications/`

User-local locations are processed last and **override** system locations. Deduplication is by `app_id` -- if the same app_id is found in multiple locations, the last one wins.

For each `.desktop` file found, proceed to Step 2.

### Step 2: Extract App ID

**File:** `lib/app/registry.sh`

1. Strip the `.desktop` extension from the filename to derive the `app_id`.
   - Example: `code.desktop` becomes `code`
   - Example: `org.mozilla.firefox.desktop` becomes `org.mozilla.firefox`
2. `validate_app_id_format()` enforces that the app_id contains only alphanumeric characters, dots, hyphens, and underscores.
3. Invalid app_ids are skipped with a warning.

### Step 3: Check App Definition Files

**File:** `lib/app/registry.sh`

1. `registry_check_app_files(app_id)` looks for the directory `lib/app-definitions/apps/<app_id>/`.
2. Checks for the existence of:
   - `metadata.json` -- Application metadata and launch option declarations.
   - `functions.sh` -- Bash functions implementing terminal launch options.
3. If both files exist: `has_terminal_launch = true`. The app supports custom terminal-based launching.
4. If the directory does not exist or files are missing: `has_terminal_launch = false`. The app can only be launched via `gtk-launch` with its `.desktop` file.

### Step 4: Extract Metadata

**File:** `lib/app/registry.sh`, `lib/utils/json-parser.sh`

Only runs if the app definition directory exists (Step 3 found files).

1. `json_get_all_metadata(metadata.json)` parses the JSON file and extracts:
   - `terminal_command` -- The binary name to check for availability (e.g., `code`, `firefox`).
2. `registry_get_app_directory_path(app_id)` returns the normalized absolute path to the app definition directory.

### Step 5: Check Reference Registry

**File:** `lib/app/registry.sh`, `lib/db/app-registry.sh`

1. `app_registry_exists(app_id)` checks whether the app_id exists in the separate read-only reference registry database. This database ships with the tool and contains pre-populated metadata for common applications.
2. If found, `app_registry_get_metadata(app_id)` returns a set of known-good defaults:
   - `app_class` -- Window class string
   - `launch_mode` -- MULTI, SINGLE, or UNIQUE
   - `window_title_pattern` -- Regex for title matching
   - `supports_pid_validation` -- Whether PID-based detection works for this app
   - `process_name` -- Expected process name
   - `has_splash_window` -- Whether the app shows a splash screen
   - `splash_duration_ms` -- How long the splash lasts
3. Reference registry data is treated as authoritative and **skips safe-mode validation** for the app.

### Step 6: Store Application

**File:** `lib/app/registry.sh`, `lib/db/app.sh`

1. `db_upsert_application_scan()` performs a conditional insert or update per app:
   - **New applications (INSERT):** All fields from Steps 2-5 are written. Reference registry data populates metadata fields. Missing fields are set to NULL.
   - **Existing applications (UPDATE):** Only scan-sourced fields are updated (desktop file path, has_terminal_launch, terminal_command). **Runtime-learned data is preserved:** app_class (if learned via detection), launch_time_ms (rolling average), safe_mode results, and splash detection data are never overwritten by a scan.
2. Track the app_id in a `found_app_ids` list for cleanup in Step 8.

### Step 7: Store Launch Options

**File:** `lib/app/registry.sh`, `lib/db/launch-options.sh`, `lib/utils/json-parser.sh`

Only runs if `has_terminal_launch = true` (Step 3).

1. `db_delete_launch_options_for_app(app_id)` clears all existing launch options and their parameters for this app. This is a full replacement, not a merge.
2. `json_get_all_launch_options(metadata.json)` parses the JSON and returns a TSV (tab-separated values) list of launch options:
   - `function_name` -- Name of the bash function in functions.sh
   - `description` -- Human-readable description
   - `params_json` -- JSON array of parameter definitions
3. For each launch option:
   - `db_add_launch_option(app_id, function_name, description)` inserts the option.
   - `db_get_launch_option_id(app_id, function_name)` retrieves the generated ID.
   - For each parameter in `params_json`: `db_add_launch_parameter(option_id, param_name, param_description, param_type, is_required)` inserts the parameter definition.

### Step 8: Cleanup

**File:** `lib/app/registry.sh`, `lib/db/app.sh`

1. `db_remove_uninstalled_applications(found_app_ids)` deletes any applications from the database whose app_id was **not** encountered during the current scan.
2. This handles the case where a user uninstalls an application -- its `.desktop` file disappears, and the next scan removes it from the registry.

---

## Module Touchpoints

| Step | Files Read | Database Operations | Module |
|------|-----------|---------------------|--------|
| 1: Iterate locations | `.desktop` files (filesystem scan) | -- | registry.sh |
| 2: Extract app_id | `.desktop` filename | -- | registry.sh, validators |
| 3: Check app definitions | metadata.json, functions.sh (existence check) | -- | registry.sh |
| 4: Extract metadata | metadata.json (content parse) | -- | json-parser.sh, registry.sh |
| 5: Reference registry | -- | app_registry (SELECT) | db/app-registry.sh |
| 6: Store application | -- | applications (INSERT/UPDATE) | db/app.sh |
| 7: Store launch options | metadata.json (launch options parse) | launch_options (DELETE + INSERT), launch_parameters (INSERT) | db/launch-options.sh, json-parser.sh |
| 8: Cleanup | -- | applications (DELETE) | db/app.sh |

---

## Edge Cases and Gotchas

1. **User .desktop files override system ones.** Because `~/.local/share/applications/` is processed last, a user-local `.desktop` file for the same app_id will replace the system version. This is important for Flatpak and Snap applications that may install both system and user `.desktop` files with different Exec lines.

2. **Runtime-learned data survives scans.** `db_upsert_application_scan` is designed to never overwrite fields that were populated by runtime detection (app_class, launch_time_ms, safe_mode validation results, splash data). This means a scan cannot "reset" an app's metadata. To fully reset, the app must be manually deleted from the database first.

3. **Launch options are fully replaced on each scan.** Unlike application metadata, launch options use a delete-then-insert strategy. This means the database IDs for launch options change on every scan. Any external references to launch_option IDs will be invalidated.

4. **Reference registry data skips safe-mode.** Apps with reference registry entries are assumed to be correctly configured. If the reference data is wrong (e.g., incorrect app_class), the app will silently fail at launch time without the safety net of safe-mode validation.

5. **Apps without .desktop files are invisible.** The discovery pipeline starts with `.desktop` file enumeration. Applications that do not install a `.desktop` file (CLI tools, custom scripts, portable apps) cannot be discovered. There is no manual registration path through the scan command.

6. **terminal_command is not validated at scan time.** The `terminal_command` extracted from metadata.json is stored as-is. Whether the binary actually exists on the system is only checked at launch time (via `command -v`). A scan can succeed even if the terminal command is not installed.

7. **Malformed metadata.json causes silent skip.** If `json_get_all_metadata` fails to parse metadata.json, the app definition is treated as if it does not exist. The app still gets registered (from its `.desktop` file) but without terminal launch support. The `kdoitall app validate` command can detect these issues separately.
