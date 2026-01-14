#!/bin/bash

check_and_set_guard "_KDOITALL_CONFIG_LOADED" || return 0

# Standard .desktop file locations
readonly DESKTOP_FILE_LOCATIONS=(
    "/usr/share/applications"
    "/usr/local/share/applications"
    "$HOME/.local/share/applications"
)

export DESKTOP_FILE_LOCATIONS