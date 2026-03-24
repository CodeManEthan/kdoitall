/*
Part of kdoitall - KDE Desktop Automation Tool
Copyright (C) 2025 Ethan Plunk
SPDX-License-Identifier: GPL-3.0-or-later
*/

PRAGMA foreign_keys = ON;

CREATE TABLE app_registry (
    app_id TEXT PRIMARY KEY,
    app_name TEXT NOT NULL UNIQUE,
    app_class TEXT NOT NULL,
    window_title_pattern TEXT,
    launch_mode TEXT,
    supports_pid_validation BOOLEAN,
    process_name TEXT,
    has_splash_window TEXT DEFAULT 'unknown'
);

-- Browsers
INSERT INTO app_registry VALUES ('org.mozilla.firefox', 'firefox', 'org.mozilla.firefox', ' — Mozilla Firefox', 'multi', 1, 'firefox', 'unknown');
--INSERT INTO app_registry VALUES ('com.google.Chrome', 'chrome', 'com.google.Chrome', 'Google Chrome', 'multi', 0, 'chrome', 'unknown');
--INSERT INTO app_registry VALUES ('org.chromium.Chromium', 'chromium', 'org.chromium.Chromium', 'Chromium', 'multi', 0, 'chromium', 'unknown');
--INSERT INTO app_registry VALUES ('com.brave.Browser', 'brave', 'com.brave.Browser', 'Brave', 'multi', 0, 'brave', 'unknown');
--INSERT INTO app_registry VALUES ('com.microsoft.Edge', 'edge', 'com.microsoft.Edge', 'Microsoft Edge', 'multi', 0, 'msedge', 'unknown');
--INSERT INTO app_registry VALUES ('com.vivaldi.Vivaldi', 'vivaldi', 'com.vivaldi.Vivaldi', 'Vivaldi', 'multi', 0, 'vivaldi', 'unknown');

-- Editors / IDEs
--INSERT INTO app_registry VALUES ('code', 'vscode', 'code', 'Visual Studio Code', 'unique', 1, 'code', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.kate', 'kate', 'org.kde.kate', 'Kate', 'multi', 1, 'kate', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.kwrite', 'kwrite', 'org.kde.kwrite', 'KWrite', 'multi', 1, 'kwrite', 'unknown');
--INSERT INTO app_registry VALUES ('sublime_text', 'sublime-text', 'sublime_text', 'Sublime Text', 'unique', 1, 'subl', 'unknown');

-- Terminals
--INSERT INTO app_registry VALUES ('org.kde.konsole', 'konsole', 'org.kde.konsole', 'Konsole', 'multi', 1, 'konsole', 'unknown');
--INSERT INTO app_registry VALUES ('Alacritty', 'alacritty', 'Alacritty', 'Alacritty', 'multi', 1, 'alacritty', 'unknown');
--INSERT INTO app_registry VALUES ('kitty', 'kitty', 'kitty', 'kitty', 'multi', 1, 'kitty', 'unknown');
--INSERT INTO app_registry VALUES ('org.wezfurlong.wezterm', 'wezterm', 'org.wezfurlong.wezterm', 'WezTerm', 'multi', 1, 'wezterm', 'unknown');
--INSERT INTO app_registry VALUES ('org.gnome.Terminal', 'gnome-terminal', 'org.gnome.Terminal.', 'Terminal', 'multi', 0, 'gnome-terminal', 'unknown');

-- File Managers
--INSERT INTO app_registry VALUES ('org.kde.dolphin', 'dolphin', 'org.kde.dolphin', 'Dolphin', 'multi', 1, 'dolphin', 'unknown');
--INSERT INTO app_registry VALUES ('org.gnome.Nautilus', 'nautilus', 'org.gnome.Nautilus', 'Files', 'multi', 1, 'nautilus', 'unknown');
--INSERT INTO app_registry VALUES ('thunar', 'thunar', 'thunar', 'Thunar', 'multi', 1, 'thunar', 'unknown');

-- Communication
--INSERT INTO app_registry VALUES ('discord', 'discord', 'discord', 'Discord', 'single', 0, 'Discord', 'unknown');
--INSERT INTO app_registry VALUES ('com.slack.Slack', 'slack', 'com.slack.Slack', 'Slack', 'single', 0, 'slack', 'unknown');
--INSERT INTO app_registry VALUES ('org.telegram.desktop', 'telegram', 'org.telegram.desktop', 'Telegram', 'single', 1, 'telegram-desktop', 'unknown');
--INSERT INTO app_registry VALUES ('org.signal.Signal', 'signal', 'org.signal.Signal', 'Signal', 'single', 0, 'signal-desktop', 'unknown');
--INSERT INTO app_registry VALUES ('org.mozilla.Thunderbird', 'thunderbird', 'org.mozilla.Thunderbird', 'Thunderbird', 'single', 1, 'thunderbird', 'unknown');

-- Media
--INSERT INTO app_registry VALUES ('org.videolan.VLC', 'vlc', 'org.videolan.VLC', 'VLC media player', 'multi', 1, 'vlc', 'unknown');
--INSERT INTO app_registry VALUES ('com.spotify.Client', 'spotify', 'com.spotify.Client', 'Spotify', 'single', 0, 'spotify', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.elisa', 'elisa', 'org.kde.elisa', 'Elisa', 'single', 1, 'elisa', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.gwenview', 'gwenview', 'org.kde.gwenview', 'Gwenview', 'multi', 1, 'gwenview', 'unknown');

-- KDE Apps
--INSERT INTO app_registry VALUES ('systemsettings', 'systemsettings', 'systemsettings', 'System Settings', 'single', 1, 'systemsettings', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.spectacle', 'spectacle', 'org.kde.spectacle', 'Spectacle', 'single', 1, 'spectacle', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.okular', 'okular', 'org.kde.okular', 'Okular', 'multi', 1, 'okular', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.ark', 'ark', 'org.kde.ark', 'Ark', 'multi', 1, 'ark', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.kcalc', 'kcalc', 'org.kde.kcalc', 'KCalc', 'single', 1, 'kcalc', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.ksysguard', 'ksysguard', 'org.kde.ksysguard', 'System Monitor', 'single', 1, 'ksysguard', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.filelight', 'filelight', 'org.kde.filelight', 'Filelight', 'single', 1, 'filelight', 'unknown');
--INSERT INTO app_registry VALUES ('org.kde.partitionmanager', 'partitionmanager', 'org.kde.partitionmanager', 'KDE Partition Manager', 'single', 1, 'partitionmanager', 'unknown');

-- Productivity
--INSERT INTO app_registry VALUES ('org.libreoffice.LibreOffice.Writer', 'libreoffice-writer', 'libreoffice', 'LibreOffice Writer', 'multi', 1, 'soffice', 'unknown');
--INSERT INTO app_registry VALUES ('org.libreoffice.LibreOffice.Calc', 'libreoffice-calc', 'libreoffice', 'LibreOffice Calc', 'multi', 1, 'soffice', 'unknown');
--INSERT INTO app_registry VALUES ('org.libreoffice.LibreOffice.Impress', 'libreoffice-impress', 'libreoffice', 'LibreOffice Impress', 'multi', 1, 'soffice', 'unknown');
--INSERT INTO app_registry VALUES ('md.obsidian.Obsidian', 'obsidian', 'md.obsidian.Obsidian', 'Obsidian', 'unique', 0, 'obsidian', 'unknown');

-- Development
--INSERT INTO app_registry VALUES ('com.axosoft.GitKraken', 'gitkraken', 'com.axosoft.GitKraken', 'GitKraken', 'single', 0, 'gitkraken', 'unknown');
--INSERT INTO app_registry VALUES ('org.sqlitebrowser.sqlitebrowser', 'sqlitebrowser', 'org.sqlitebrowser.sqlitebrowser', 'DB Browser for SQLite', 'multi', 1, 'sqlitebrowser', 'unknown');
--INSERT INTO app_registry VALUES ('com.getpostman.Postman', 'postman', 'com.getpostman.Postman', 'Postman', 'single', 0, 'postman', 'unknown');
