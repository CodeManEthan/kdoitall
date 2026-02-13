/* 
Part of kdoitall - KDE Desktop Automation Tool
Copyright (C) 2025 Ethan Plunk
SPDX-License-Identifier: GPL-3.0-or-later
*/

PRAGMA foreign_keys = ON;

CREATE TABLE workspace_definitions (
    workspace_name TEXT PRIMARY KEY,
    description TEXT,
    is_active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_opened_at TIMESTAMP
);

CREATE TABLE app_windows (
    workspace_name TEXT NOT NULL,
    window_name TEXT PRIMARY KEY,
    uuid TEXT NOT NULL UNIQUE,
    class TEXT NOT NULL,
    pid INTEGER,
    window_title TEXT,
    app_id TEXT,
    is_tab BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (workspace_name) REFERENCES workspaces(workspace_name) ON DELETE CASCADE,
    FOREIGN KEY (app_id) REFERENCES applications(app_id) ON DELETE SET NULL
);

CREATE TABLE tabs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    window_name TEXT NOT NULL,
    tab_name TEXT NOT NULL,
    tab_number INTEGER,
    FOREIGN KEY (window_name) REFERENCES windows(window_name) ON DELETE CASCADE,
    UNIQUE(window_name, tab_number)
);

CREATE TABLE applications (
    app_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    desktop_file_path TEXT,
    app_class TEXT,
    window_title_pattern TEXT,
    launch_mode TEXT,
    has_terminal_launch BOOLEAN DEFAULT FALSE,
    has_desktop_launch BOOLEAN DEFAULT FALSE,
    supports_pid_validation BOOLEAN,
    executable_path TEXT,
    process_name TEXT,
    launch_time_ms INTEGER,
    last_launch_time_ms INTEGER,
    launch_time_samples INTEGER DEFAULT 0,
    requires_safe_mode BOOLEAN DEFAULT FALSE,
    safe_mode_completed BOOLEAN DEFAULT FALSE,
    safe_mode_timestamp TIMESTAMP,
    app_directory_path TEXT,
    terminal_command TEXT, 
    last_validated TIMESTAMP
);

CREATE TABLE launch_options (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_id TEXT NOT NULL,
    function_name TEXT NOT NULL,
    description TEXT NOT NULL,
    display_order INTEGER DEFAULT 0,
    FOREIGN KEY (app_id) REFERENCES applications(app_id) ON DELETE CASCADE,
    UNIQUE(app_id, function_name)
);

CREATE TABLE launch_parameters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    app_id TEXT NOT NULL,
    function_id INTEGER NOT NULL,
    parameter_name TEXT NOT NULL,
    description TEXT NOT NULL,
    display_order INTEGER NOT NULL,
    FOREIGN KEY (app_id) REFERENCES applications(app_id) ON DELETE CASCADE,
    FOREIGN KEY (function_id) REFERENCES launch_options(id) ON DELETE CASCADE,
    UNIQUE(app_id, function_id, parameter_name)
);

CREATE INDEX idx_launch_options_app_id ON launch_options(app_id);

CREATE TRIGGER auto_tab_number
AFTER INSERT ON tabs
FOR EACH ROW
WHEN NEW.tab_number IS NULL
BEGIN
    UPDATE tabs
    SET tab_number = (
        SELECT COALESCE(MAX(tab_number), 0) + 1
        FROM tabs
        WHERE window_name = NEW.window_name AND id != NEW.id
    )
    WHERE id = NEW.id;
END;