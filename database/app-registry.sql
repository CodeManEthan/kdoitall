/*
Part of kdoitall - KDE Desktop Automation Tool
Copyright (C) 2025 Ethan Plunk
SPDX-License-Identifier: GPL-3.0-or-later
*/

PRAGMA foreign_keys = ON;

CREATE TABLE app_registry (
    app_id TEXT PRIMARY KEY,
    app_class TEXT NOT NULL,
    window_title_pattern TEXT,
    launch_mode TEXT,
    supports_pid_validation BOOLEAN,
    process_name TEXT
);

-- Browsers
INSERT INTO app_registry VALUES ('org.mozilla.firefox', 'org.mozilla.firefox', ' — Mozilla Firefox', 'multi', 1, 'firefox');
--INSERT INTO app_registry VALUES ('com.google.Chrome', 'com.google.Chrome', 'Google Chrome', 'multi', 0, 'chrome');
--INSERT INTO app_registry VALUES ('org.chromium.Chromium', 'org.chromium.Chromium', 'Chromium', 'multi', 0, 'chromium');
--INSERT INTO app_registry VALUES ('com.brave.Browser', 'com.brave.Browser', 'Brave', 'multi', 0, 'brave');
--INSERT INTO app_registry VALUES ('com.microsoft.Edge', 'com.microsoft.Edge', 'Microsoft Edge', 'multi', 0, 'msedge');
--INSERT INTO app_registry VALUES ('com.vivaldi.Vivaldi', 'com.vivaldi.Vivaldi', 'Vivaldi', 'multi', 0, 'vivaldi');

-- Editors / IDEs
--INSERT INTO app_registry VALUES ('code', 'code', 'Visual Studio Code', 'unique', 1, 'code');
--INSERT INTO app_registry VALUES ('org.kde.kate', 'org.kde.kate', 'Kate', 'multi', 1, 'kate');
--INSERT INTO app_registry VALUES ('org.kde.kwrite', 'org.kde.kwrite', 'KWrite', 'multi', 1, 'kwrite');
--INSERT INTO app_registry VALUES ('sublime_text', 'sublime_text', 'Sublime Text', 'unique', 1, 'subl');

-- Terminals
--INSERT INTO app_registry VALUES ('org.kde.konsole', 'org.kde.konsole', 'Konsole', 'multi', 1, 'konsole');
--INSERT INTO app_registry VALUES ('Alacritty', 'Alacritty', 'Alacritty', 'multi', 1, 'alacritty');
--INSERT INTO app_registry VALUES ('kitty', 'kitty', 'kitty', 'multi', 1, 'kitty');
--INSERT INTO app_registry VALUES ('org.wezfurlong.wezterm', 'org.wezfurlong.wezterm', 'WezTerm', 'multi', 1, 'wezterm');
--INSERT INTO app_registry VALUES ('org.gnome.Terminal', 'org.gnome.Terminal.', 'Terminal', 'multi', 0, 'gnome-terminal');

-- File Managers
--INSERT INTO app_registry VALUES ('org.kde.dolphin', 'org.kde.dolphin', 'Dolphin', 'multi', 1, 'dolphin');
--INSERT INTO app_registry VALUES ('org.gnome.Nautilus', 'org.gnome.Nautilus', 'Files', 'multi', 1, 'nautilus');
--INSERT INTO app_registry VALUES ('thunar', 'thunar', 'Thunar', 'multi', 1, 'thunar');

-- Communication
--INSERT INTO app_registry VALUES ('discord', 'discord', 'Discord', 'single', 0, 'Discord');
--INSERT INTO app_registry VALUES ('com.slack.Slack', 'com.slack.Slack', 'Slack', 'single', 0, 'slack');
--INSERT INTO app_registry VALUES ('org.telegram.desktop', 'org.telegram.desktop', 'Telegram', 'single', 1, 'telegram-desktop');
--INSERT INTO app_registry VALUES ('org.signal.Signal', 'org.signal.Signal', 'Signal', 'single', 0, 'signal-desktop');
--INSERT INTO app_registry VALUES ('org.mozilla.Thunderbird', 'org.mozilla.Thunderbird', 'Thunderbird', 'single', 1, 'thunderbird');

-- Media
--INSERT INTO app_registry VALUES ('org.videolan.VLC', 'org.videolan.VLC', 'VLC media player', 'multi', 1, 'vlc');
--INSERT INTO app_registry VALUES ('com.spotify.Client', 'com.spotify.Client', 'Spotify', 'single', 0, 'spotify');
--INSERT INTO app_registry VALUES ('org.kde.elisa', 'org.kde.elisa', 'Elisa', 'single', 1, 'elisa');
--INSERT INTO app_registry VALUES ('org.kde.gwenview', 'org.kde.gwenview', 'Gwenview', 'multi', 1, 'gwenview');

-- KDE Apps
--INSERT INTO app_registry VALUES ('systemsettings', 'systemsettings', 'System Settings', 'single', 1, 'systemsettings');
--INSERT INTO app_registry VALUES ('org.kde.spectacle', 'org.kde.spectacle', 'Spectacle', 'single', 1, 'spectacle');
--INSERT INTO app_registry VALUES ('org.kde.okular', 'org.kde.okular', 'Okular', 'multi', 1, 'okular');
--INSERT INTO app_registry VALUES ('org.kde.ark', 'org.kde.ark', 'Ark', 'multi', 1, 'ark');
--INSERT INTO app_registry VALUES ('org.kde.kcalc', 'org.kde.kcalc', 'KCalc', 'single', 1, 'kcalc');
--INSERT INTO app_registry VALUES ('org.kde.ksysguard', 'org.kde.ksysguard', 'System Monitor', 'single', 1, 'ksysguard');
--INSERT INTO app_registry VALUES ('org.kde.filelight', 'org.kde.filelight', 'Filelight', 'single', 1, 'filelight');
--INSERT INTO app_registry VALUES ('org.kde.partitionmanager', 'org.kde.partitionmanager', 'KDE Partition Manager', 'single', 1, 'partitionmanager');

-- Productivity
--INSERT INTO app_registry VALUES ('org.libreoffice.LibreOffice.Writer', 'libreoffice', 'LibreOffice Writer', 'multi', 1, 'soffice');
--INSERT INTO app_registry VALUES ('org.libreoffice.LibreOffice.Calc', 'libreoffice', 'LibreOffice Calc', 'multi', 1, 'soffice');
--INSERT INTO app_registry VALUES ('org.libreoffice.LibreOffice.Impress', 'libreoffice', 'LibreOffice Impress', 'multi', 1, 'soffice');
--INSERT INTO app_registry VALUES ('md.obsidian.Obsidian', 'md.obsidian.Obsidian', 'Obsidian', 'unique', 0, 'obsidian');

-- Development
--INSERT INTO app_registry VALUES ('com.axosoft.GitKraken', 'com.axosoft.GitKraken', 'GitKraken', 'single', 0, 'gitkraken');
--INSERT INTO app_registry VALUES ('org.sqlitebrowser.sqlitebrowser', 'org.sqlitebrowser.sqlitebrowser', 'DB Browser for SQLite', 'multi', 1, 'sqlitebrowser');
--INSERT INTO app_registry VALUES ('com.getpostman.Postman', 'com.getpostman.Postman', 'Postman', 'single', 0, 'postman');
