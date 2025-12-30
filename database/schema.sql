PRAGMA foreign_keys = ON;

CREATE TABLE workspaces (
    workspace_name TEXT PRIMARY KEY, 
    is_active BOOLEAN DEFAULT FALSE
);

CREATE TABLE app_windows (
    workspace_name TEXT NOT NULL,
    window_name TEXT PRIMARY KEY,
    uuid TEXT NOT NULL UNIQUE,
    class TEXT NOT NULL,
    is_tab BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (workspace_name) REFERENCES workspaces(workspace_name) ON DELETE CASCADE
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
    has_terminal_launch BOOLEAN DEFAULT FALSE,
    has_desktop_launch BOOLEAN DEFAULT FALSE,
    app_file_path TEXT,
    last_validated TIMESTAMP
);

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