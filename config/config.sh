#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Standard .desktop file locations
readonly DESKTOP_FILE_LOCATIONS=(
    "/usr/share/applications"
    "/usr/local/share/applications"
    "$HOME/.local/share/applications"
)

export DESKTOP_FILE_LOCATIONS