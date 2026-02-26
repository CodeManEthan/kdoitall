# Changelog

All notable changes to kdoitall will be documented in this file.

## [Unreleased]

### Added

- **Quick action command** (`kdoitall quick`) — interactive window picker for ad-hoc window manipulation without workspace definitions. Supports focus, minimize, close, move, and combo moves with dot-skip syntax.
- **16 optional window positions** — two-thirds, 60/40, 40/60, center, and quarter splits in both orientations, enabled via `EXTRA_POSITIONS` in user config.
- **Workspace focus and minimize commands** — raise or minimize all windows in an active workspace.
- **Post-open focus window** — choose a window to automatically focus after workspace open, switching to its virtual desktop.
- **App registry reference database** — infrastructure in place for a pre-populated reference database of common applications to reduce safe-mode dependency. Entries will be added individually in future releases.
- **`kdoitall update` command** — pulls latest changes and rebuilds the app registry.
- **`kdoitall status` command** — shows active workspace state with live window geometry.
- **Tiered logging** (`--info` flag) and optional file logging via `LOG_TO_FILE` config.
- **Automated kdotool setup** — install script now offers automatic download and installation.
- **Flatpak and Snap desktop file directories** added to default search locations.
- **`EXTRA_POSITIONS` config option** — opt-in to 16 additional window positions beyond the 12 defaults.
- **`LOG_TO_FILE` config option** — enable file logging to capture full verbose output to timestamped log files.
- **`CLOSE_WAIT_TIMEOUT` config option** — configurable timeout for assisted window close during workspace close.

### Changed

- **Safe-mode streamlined** — replaced multi-step interactive process with automatic metadata detection and a single confirmation prompt.
- **Command abbreviations** — short aliases for all commands (e.g., `ws`, `win`, `scr`, `q`).

## [0.1.0] - 2026-02-13

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
