-- Migration 001: Add terminal_emulators table
--
-- Introduced in v0.2.1 alongside the terminal-emulator detection feature.
-- DBs created from v0.2.0 or earlier do not have this table; this migration
-- backfills it. Uses IF NOT EXISTS so it is also safe to apply against any
-- DB that already happens to have the table.

CREATE TABLE IF NOT EXISTS terminal_emulators (
    app_id TEXT PRIMARY KEY,
    exec_flag TEXT NOT NULL DEFAULT '-e',
    detection_source TEXT NOT NULL DEFAULT 'auto',
    FOREIGN KEY (app_id) REFERENCES applications(app_id) ON DELETE CASCADE
);
