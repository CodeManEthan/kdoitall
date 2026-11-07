# Changelog

All notable changes to kdoitall will be documented in this file.

## \[Unreleased\]

## \[0.2.2\] - 2026-11-07

### Added

- **Window snapshots in one call** — kdoitall can now read the whole window list through a small KWin script in one call, instead of asking `kdotool` about each window. A daemon on the session bus (`org.kdoitall.Snapshot`) carries the result back; kdoitall starts it on first use. This needs the Python `dbus` and `gi` modules (python3-dbus, python3-gobject) and `qdbus-qt6` or `qdbus6`. Without them kdoitall falls back to `kdotool`, as before.
- `--restart-snapshot-daemon` **flag** — stops the snapshot daemon and starts a new one.
- **Continuous integration** — every push and pull request runs `bash -n` and `shellcheck` on every shell file, compiles the Python files, runs the unit tests, and checks that `--help` and `--version` work on a machine with no KDE tools.
- **Unit tests** (`tests/unit/run.sh`) — run anywhere, with no KDE session, database or windows. They cover the workspace script generator, params validation, the terminal launch functions, the data directory, the user config, the qdbus choice, and that `--help` names every command the README shows.
- **README sections** — how kdoitall works (scan, define, open, and what safe mode does on first open), the workspace file format with an example and a note on files you didn't write, a table of all 28 positions, every configuration setting with its default, the quick picker and combo move, and how to run the tests. Requirements now say what kdoitall is tested on.

### Changed

- `--help` **and** `--version` **work without KDE tools** — they print and exit before the dependency check, the database and screen detection, so they work on any Linux machine with bash. Running `kdoitall` with no command prints the usage instead of "Unknown command".
- `--help` **lists every command** — it now includes `workspace export`, `workspace create --from-file <json> [--replace]`, `workspace open --skip`, `workspace list --details`, the non-interactive `workspace edit` flags, `app name`, `app set-terminal` and `app unset-terminal`. `window move` shows its real arguments, `<window-name> <desktop> [screen] [position]`. The CONFIGURATION section lists every setting with its default.
- **python3 is checked at startup** — like the other required tools, a missing `python3` is now reported by name with the install command for your package manager, before anything tries to run it.
- **The integration tests use a throwaway data directory** — each `tests/run-tests.sh` run gets a fresh database in a new temporary directory, deleted when the run ends. Your own database and workspace scripts are never read or written.

### Fixed

- **Workspace scripts pass stored values through literally** — names, screens and params reach the launch function exactly as stored, as one argument each. Quotes, `$` and backticks in them are no longer read by the shell. Launch function names and positions must be plain names. Params containing `|`, a newline or another control character (tabs separate values) are refused wherever params come in, and an empty tab-separated value is kept rather than dropped. The terminal launch functions still run the commands and scripts a workspace names, since that is what they are for, so import only workspace files you trust. Scripts written by earlier versions keep working. To regenerate one: `kdoitall workspace export <name> > f.json`, then `kdoitall workspace create <name> --from-file f.json --replace`.
- **The terminal launch functions quote paths** — a directory, virtualenv or script path containing a `'` no longer breaks the command the terminal runs.
- **Splash screen auto-learn** — kdoitall now watches long enough to see a splash screen close, records that the app has one and how long it lasted, and uses that on later launches. Still partial: an app that opens a second window alongside its main one after the splash (GIMP's welcome dialog, for example) can fail its first open or have the dialog positioned instead of the main window.
- `DESKTOP_FILE_LOCATIONS` **can be set in the user config** — setting it there used to stop every command with a "readonly variable" error.
- `qdbus6` **is used when** `qdbus-qt6` **is missing** — it was accepted by the dependency check but never called, so the snapshot path silently fell back to `kdotool`.
- **Install script exit** — after it had installed `kdotool` itself, `scripts/install.sh` could end with an "unbound variable" error and left its temporary download directory behind.
- **Launch crash when an app has no class yet** — a single-instance app with no learned window class stopped the launch with an "unbound variable" error. Several error paths referred to error codes that were never defined; they now use real ones.
- **Launch stopped by an empty window title** — when the window title read came back empty just after a window appeared, the whole launch failed. The window is now registered anyway, and a window that closed before it could be registered gets a clear error.
- **Safe mode printed a window ID** after each app it checked.
- **Workspace subcommands and** `--help` — `workspace create --help` started creating a workspace named `--help`, and `workspace delete --help` looked for one. Every workspace subcommand now prints its usage for `--help` or `-h`.

### Removed

- **Unused browser-tab code** — the ydotool key-press helpers and the tab module, pieces of a browser-tab feature that was never built. No command used them.

## \[0.2.1\] - 2026-04-28

0.2.0 was tagged without its own entry here. Its changes are folded into this one.

### Added

- **Quick action command** (`kdoitall quick`) — interactive window picker for ad-hoc window manipulation without workspace definitions. Supports focus, minimize, close, move, and combo moves with dot-skip syntax.
- **16 optional window positions** — two-thirds, 60/40, 40/60, center, and quarter splits in both orientations, enabled via `EXTRA_POSITIONS` in user config.
- **Workspace focus and minimize commands** — raise or minimize all windows in an active workspace.
- **Post-open focus window** — choose a window to automatically focus after workspace open, switching to its virtual desktop.
- **Terminal emulator support** — `app set-terminal` / `unset-terminal` commands and a shared launch-options system with layered detection for terminal-based apps.
- **Non-interactive workspace edit** — `workspace edit` now accepts `--description` and `--focus-window` flags for scripted updates.
- **Auto-generated app names during scan** — `app scan` populates a human-friendly `app_name` column; `app name` command provides manual override and reset.
- **JSON-config workspace creation** — `workspace create --from-file <path>` (with optional `--replace`) and `workspace export` for round-tripping definitions.
- **Splash window handling** — initial support for apps that briefly show a splash screen during startup. Detected behavior is auto-learned per-app and used to improve subsequent launches. (Coverage of edge cases is ongoing.)
- `SAFE_MODE_STRICTNESS` **config option** — `relaxed` (default) prompts only when app class is missing; `strict` also prompts when launch mode or splash window is unknown.
- **Display-name resolution for** `app info` — accepts display names in addition to app IDs, with an interactive disambiguation menu when names collide.
- **Active workspace guards** — destructive operations refuse to run against active workspaces with clear error messages.
- **Automatic database upgrades** — schema changes apply transparently when you run kdoitall after pulling new versions; no manual reset required.
- `--skip` flag for `workspace open` — bypasses safe-mode prompts when launching workspaces with apps that haven't been profiled yet.
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

- **Window-detection reliability** — improved resilience to occasional kdotool/KWin compositor flakiness, especially on systems with many open windows. Reduces cases where windows could be incorrectly removed from kdoitall's tracking after a transient compositor stutter.

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
