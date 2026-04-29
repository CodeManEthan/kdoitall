# Changelog

All notable changes to kdoitall will be documented in this file.

## \[Unreleased\]

### Added

- **Forward-only schema migration system** — schema changes apply automatically at every startup via numbered SQL files in `database/migrations/`, tracked in a new `schema_migrations` table. Fresh installs and dev-resets continue to build from `database/schema.sql` and stamp existing migrations as pre-applied, so the same migration never runs twice.

## \[0.2.1\] - 2026-04-28

### Added

- **Quick action command** (`kdoitall quick`) — interactive window picker for ad-hoc window manipulation without workspace definitions. Supports focus, minimize, close, move, and combo moves with dot-skip syntax.
- **16 optional window positions** — two-thirds, 60/40, 40/60, center, and quarter splits in both orientations, enabled via `EXTRA_POSITIONS` in user config.
- **Workspace focus and minimize commands** — raise or minimize all windows in an active workspace.
- **Post-open focus window** — choose a window to automatically focus after workspace open, switching to its virtual desktop.
- **Terminal emulator support** — `app set-terminal` / `unset-terminal` commands and a shared launch-options system with layered detection for terminal-based apps.
- **Non-interactive workspace edit** — `workspace edit` now accepts `--description` and `--focus-window` flags for scripted updates.
- **Auto-generated app names during scan** — `app scan` populates a human-friendly `app_name` column; `app name` command provides manual override and reset.
- **JSON-config workspace creation** — `workspace create --from-file <path>` (with optional `--replace`) and `workspace export` for round-tripping definitions.
- **Splash window detection pipeline** — tri-state `has_splash_window` tracking, `splash_duration_ms`, stability polling, transient window filtering, and grace periods for reliable detection of apps with splash screens.
- `SAFE_MODE_STRICTNESS` **config option** — `relaxed` (default) prompts only when app class is missing; `strict` also prompts when launch mode or splash window is unknown.
- **Display-name resolution for** `app info` — accepts display names in addition to app IDs, with an interactive disambiguation menu when names collide.
- **Active workspace guards** — destructive operations refuse to run against active workspaces with clear error messages.
- **Expanded automated test suite** — new tests for auto-detect sync, simultaneous workspaces, complex workspaces, launch modes, splash windows, and active-workspace guards (tests 11–16) plus a kdotool search test, with a `--skip` flag to bypass safe mode during `workspace open`.
- **App registry reference database** — infrastructure in place for a pre-populated reference database of common applications to reduce safe-mode dependency. Entries will be added individually in future releases.
- `build-app-registry.sh` **script** — utility for populating the reference database.
- **Project documentation tree** (`docs/`) — module references, end-to-end flow guides, and structural-change checklists.
- `kdoitall update` **command** — pulls latest changes and rebuilds the app registry.
- `kdoitall status` **command** — shows active workspace state with live window geometry.
- **Tiered logging** (`--info` flag) and optional file logging via `LOG_TO_FILE` config.
- **Automated kdotool setup** — install script now offers automatic download and installation.
- **Flatpak and Snap desktop file directories** added to default search locations.
- `EXTRA_POSITIONS` **config option** — opt-in to 16 additional window positions beyond the 12 defaults.
- `LOG_TO_FILE` **config option** — enable file logging to capture full verbose output to timestamped log files.
- `CLOSE_WAIT_TIMEOUT` **config option** — configurable timeout for assisted window close during workspace close.

### Changed

- **Safe-mode streamlined** — replaced multi-step interactive process with automatic metadata detection and a single confirmation prompt.
- **Command abbreviations** — short aliases for all commands (e.g., `ws`, `win`, `scr`, `q`).
- `app scan` **upsert logic** — preserves safe-mode and runtime metadata across rescans instead of resetting it.
- **Uninstalled app cleanup** — `app scan` removes applications whose `.desktop` files no longer exist on the system.
- **Case-insensitive listings** — application and workspace listings sort with `COLLATE NOCASE` for natural ordering.

### Fixed

- **Database hardening** — fixes uncovered by the expanded test suite, including silent `SELECT changes()` failures, parallel-array misalignment in window detection, and NULL handling in safe-mode predicates (`COALESCE` for tri-state columns).

## \[0.1.0\] - 2026-02-13

Initial public release.

- Workspace creation with interactive multi-window configuration
- Application scanning from `.desktop` files
- Window detection and positioning across virtual desktops and screens
- Screen alias system with database-backed persistent names
- Custom window naming during workspace creation
- Window management commands (list, status, close, open, move, focus, minimize)
- Safe-mode for gathering application metadata
- Two-tier configuration system (project defaults + user overrides)
- Multi-distribution package manager support
- XDG-compliant directory structure
