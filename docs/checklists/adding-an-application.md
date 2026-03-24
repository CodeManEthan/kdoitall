# Adding Support for a New Application

This checklist covers adding terminal launch support for a new application. Desktop-only apps (gtk-launch) are auto-discovered by `app scan` and don't need definition files.

## 1. Identify App ID

- [ ] Find the application's .desktop file (check /usr/share/applications/, ~/.local/share/applications/)
- [ ] Extract app_id from filename (e.g., `org.mozilla.firefox.desktop` -> `org.mozilla.firefox`)
- [ ] Verify format: alphanumeric, dots, hyphens, underscores only (validated by `validate_app_id_format()` in `lib/utils/validators.sh`)

## 2. Create App Definition Directory

- [ ] Create directory: `lib/app-definitions/apps/<app_id>/`
- [ ] Create `metadata.json` with required structure:
  - `terminal_command`: binary name for availability check (must be in PATH)
  - `launch_options`: array of objects with `function_name`, `description`, optional `parameters` array
  - Parameters use PascalCase naming (validated by `json_validate_metadata()` in `lib/app-definitions/validator.sh`)
- [ ] Create `functions.sh` with source guard and `load_app_metadata` call

## 3. Implement functions.sh

- [ ] Add source guard: `check_and_set_guard "_KDOITALL_<APPNAME>_LOADED" || return 0`
- [ ] Source dependencies: `lib/core/core.sh`, `lib/app-definitions/loader.sh`, `lib/db/app.sh`
- [ ] Call `load_app_metadata "${BASH_SOURCE[0]%/*}"` to initialize APP_ID, TERMINAL_COMMAND, LAUNCH_TYPE
- [ ] Implement internal launch helper `_launch_<app>()` that runs the binary with `> /dev/null 2>&1 & disown`
- [ ] Implement each launch function declared in metadata.json
  - Standard signature: `function_name(workspace_name, window_name, desktop, screen, position, [custom_params...])`
  - Call `db_get_app_launch_properties(app_id)` to get class, launch_mode, etc.
  - Call `execute_launch_window()` with all required parameters
  - Set window_title_pattern for reliable detection
- [ ] Validate parameter count matches metadata.json declarations

## 4. Validate Definition Files

- [ ] Run `kdoitall app validate` -- should pass with no errors
- [ ] Check that function names in metadata.json match actual function declarations in functions.sh
- [ ] Check parameter names are PascalCase format

## 5. Register Application

- [ ] Run `kdoitall app scan` to discover and register the application
- [ ] Run `kdoitall app info <app_id>` to verify metadata was stored correctly
- [ ] Run `kdoitall app options <app_id>` to verify launch options and parameters

## 6. Consider Reference Registry (optional)

- [ ] If app metadata is well-known (class, launch_mode, splash behavior), add entry to `database/app-registry.sql`
- [ ] Reference registry data skips safe-mode validation -- only add confirmed values
- [ ] Fields: app_id, app_name, app_class, launch_mode, window_title_pattern, supports_pid_validation, process_name, has_splash_window, splash_duration_ms

## 7. Test

- [ ] Create a test workspace using the new app: `kdoitall workspace create test-<app>`
- [ ] Open the workspace: `kdoitall --verbose workspace open test-<app>`
- [ ] Verify window detection, positioning, and class caching work correctly
- [ ] Close the workspace: `kdoitall --verbose workspace close test-<app>`
- [ ] If safe-mode triggered, complete it and verify stored metadata
- [ ] Delete test workspace: `kdoitall workspace delete test-<app>`

## 8. Update Documentation

- [ ] Update `docs/modules/app-registry.md` if the app introduces new patterns
- [ ] If the app has unique launch behavior, document in the function comments
