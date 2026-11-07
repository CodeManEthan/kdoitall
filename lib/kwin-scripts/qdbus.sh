#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Picks the qdbus binary the snapshot client calls. Distros ship the Qt 6
# build as qdbus-qt6 or as qdbus6. Sourced by lib/kwin-scripts/snapshot.sh,
# which runs on its own without the rest of kdoitall, so this file has no
# dependencies.

[[ -n "${_KDOITALL_QDBUS_LOADED:-}" ]] && return 0
_KDOITALL_QDBUS_LOADED=1

# select_qdbus_bin
# Prints the qdbus command to use: QDBUS_BIN when set, else qdbus-qt6 when
# it is on PATH, else qdbus6. Does not check that qdbus6 exists; callers
# that need to know check availability first (see snapshot_available).
select_qdbus_bin() {
    if [[ -n "${QDBUS_BIN:-}" ]]; then
        printf '%s\n' "$QDBUS_BIN"
    elif command -v qdbus-qt6 &>/dev/null; then
        printf '%s\n' "qdbus-qt6"
    else
        printf '%s\n' "qdbus6"
    fi
}
