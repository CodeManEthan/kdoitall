#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_dependencies() {
    local -a missing=()

    # Check each required command
    local -a required_commands=(kdotool jq kscreen-doctor sqlite3 python3 gtk-launch)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    # Nothing missing, return early
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    # Detect package manager and build install command
    local pm="" install_cmd=""
    local -A pkg_map

    if command -v dnf &> /dev/null; then
        pm="dnf"
        install_cmd="sudo dnf install"
        pkg_map=(
            [kscreen-doctor]="kscreen"
            [sqlite3]="sqlite"
            [python3]="python3"
            [gtk-launch]="glib2"
        )
    elif command -v apt &> /dev/null; then
        pm="apt"
        install_cmd="sudo apt install"
        pkg_map=(
            [kscreen-doctor]="kscreen"
            [sqlite3]="sqlite3"
            [python3]="python3"
            [gtk-launch]="libglib2.0-bin"
        )
    elif command -v pacman &> /dev/null; then
        pm="pacman"
        install_cmd="sudo pacman -S"
        pkg_map=(
            [kscreen-doctor]="kscreen"
            [sqlite3]="sqlite"
            [python3]="python"
            [gtk-launch]="glib2"
        )
    elif command -v zypper &> /dev/null; then
        pm="zypper"
        install_cmd="sudo zypper install"
        pkg_map=(
            [kscreen-doctor]="kscreen"
            [sqlite3]="sqlite3"
            [python3]="python3"
            [gtk-launch]="glib2-tools"
        )
    fi

    echo "Error: Missing dependencies: ${missing[*]}" >&2
    echo "" >&2

    if [[ -n "$pm" ]]; then
        local -a packages=()
        for cmd in "${missing[@]}"; do
            packages+=("${pkg_map[$cmd]:-$cmd}")
        done
        echo "Install with:" >&2
        echo "  ${install_cmd} ${packages[*]}" >&2
    else
        echo "Could not detect package manager. Please install: ${missing[*]}" >&2
    fi

    exit 1
}

check_and_set_guard() {
    local guard_var="$1"

    if [[ -n "${!guard_var:-}" ]]; then
        return 1  # Already sourced (failure = don't continue)
    fi

    # Set the guard variable in the caller's scope
    printf -v "$guard_var" "1"
    return 0  # Not sourced yet (success = continue)
}

# Soft check for the optional KWin-script snapshot path
# (lib/kwin-scripts/snapshot.sh). When all deps are present, kdoitall uses
# the race-free atomic snapshot for window queries; when missing, it falls
# back to the kdotool query path (still functional, just race-prone).
# Returns 0 always — emits a debug log either way so verbose runs surface
# which path is in use.
check_snapshot_dependencies() {
    local function_name="check_snapshot_dependencies"
    local -a missing=()

    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    elif ! python3 -c "import dbus, dbus.service, dbus.mainloop.glib; from gi.repository import GLib" &>/dev/null; then
        missing+=("python3-dbus / python3-gobject")
    fi

    if ! command -v qdbus-qt6 &>/dev/null && ! command -v qdbus6 &>/dev/null; then
        missing+=("qdbus-qt6")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        debug_log "$function_name" "KWin snapshot deps missing (${missing[*]}); using kdotool fallback for queries"
    else
        debug_log "$function_name" "KWin snapshot deps available; race-free query path enabled"
    fi
    return 0
}