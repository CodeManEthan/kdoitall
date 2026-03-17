#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Shared config utilities for install and dev-reset scripts

update_user_config() {
    local config_file="$1"
    local -a added_options=()

    # Each entry: "VARIABLE_NAME|block text to append"
    # The variable name is used to detect whether the option already exists.
    local -a config_blocks=(
        'DESKTOP_FILE_LOCATIONS|# Standard .desktop file locations
# DESKTOP_FILE_LOCATIONS=(
#     "/usr/share/applications"
#     "/usr/local/share/applications"
#     "$HOME/.local/share/applications"
#     "/var/lib/flatpak/exports/share/applications"
#     "$HOME/.local/share/flatpak/exports/share/applications"
#     "/var/lib/snapd/desktop/applications"
# )'
        'SAFE_MODE_PROMPTING|# Safe-mode prompting during workspace open
# SAFE_MODE_PROMPTING="enabled"'
        'SAFE_MODE_STRICTNESS|# Safe-mode strictness level
# "relaxed" — only prompt if app class is missing
# "strict"  — prompt if app class, launch mode, or splash window is missing
# SAFE_MODE_STRICTNESS="relaxed"'
        'LOG_TO_FILE|# File logging (writes full verbose output to log file regardless of CLI flag)
# LOG_TO_FILE="disabled"'
        'LOG_DIR|# Log directory (only used when LOG_TO_FILE is enabled)
# LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/kdoitall/logs"'
        'CLOSE_WAIT_TIMEOUT|# Timeout (seconds) per window during assisted close before auto-skipping
# CLOSE_WAIT_TIMEOUT=60'
        'EXTRA_POSITIONS|# Extra window positions (uncomment the array and desired positions to enable)
# EXTRA_POSITIONS=(
#     "Left Two-Thirds"
#     "Right Two-Thirds"
#     "Left 60"
#     "Right 40"
#     "Left 40"
#     "Right 60"
#     "Center Half"
#     "Left 25"
#     "Right 25"
#     "Center Two-Thirds"
#     "Top Two-Thirds"
#     "Bottom Two-Thirds"
#     "Top 60"
#     "Bottom 40"
#     "Top 40"
#     "Bottom 60"
# )'
    )

    local entry=""
    local var_name=""
    local block_text=""
    for entry in "${config_blocks[@]}"; do
        var_name="${entry%%|*}"
        block_text="${entry#*|}"

        if ! grep -q "$var_name" "$config_file"; then
            printf '\n%s\n' "$block_text" >> "$config_file"
            added_options+=("$var_name")
        fi
    done

    if [[ ${#added_options[@]} -gt 0 ]]; then
        echo "✓ User config updated with ${#added_options[@]} new option(s): $config_file"
        for var_name in "${added_options[@]}"; do
            echo "    + $var_name"
        done
    else
        echo "✓ User config is up-to-date:  $config_file"
    fi
}
