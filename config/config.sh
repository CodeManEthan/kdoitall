#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

# Standard .desktop file locations
readonly DESKTOP_FILE_LOCATIONS=(
    "/usr/share/applications"
    "/usr/local/share/applications"
    "$HOME/.local/share/applications"
)

export DESKTOP_FILE_LOCATIONS