#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_dependencies() {
    local -a missing=()
    local -a manual=()

    # Check each required command
    local -a required_commands=(kdotool jq bc kscreen-doctor sqlite3 gtk-launch)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            if [[ "$cmd" == "kdotool" ]]; then
                manual+=("kdotool")
            else
                missing+=("$cmd")
            fi
        fi
    done

    # Nothing missing, return early
    if [[ ${#missing[@]} -eq 0 && ${#manual[@]} -eq 0 ]]; then
        return 0
    fi

    # Detect package manager and build install command
    if [[ ${#missing[@]} -gt 0 ]]; then
        local pm="" install_cmd=""
        local -A pkg_map

        if command -v dnf &> /dev/null; then
            pm="dnf"
            install_cmd="sudo dnf install"
            pkg_map=(
                [kscreen-doctor]="kscreen"
                [sqlite3]="sqlite"
                [gtk-launch]="glib2"
            )
        elif command -v apt &> /dev/null; then
            pm="apt"
            install_cmd="sudo apt install"
            pkg_map=(
                [kscreen-doctor]="kscreen"
                [sqlite3]="sqlite3"
                [gtk-launch]="libglib2.0-bin"
            )
        elif command -v pacman &> /dev/null; then
            pm="pacman"
            install_cmd="sudo pacman -S"
            pkg_map=(
                [kscreen-doctor]="kscreen"
                [sqlite3]="sqlite"
                [gtk-launch]="glib2"
            )
        elif command -v zypper &> /dev/null; then
            pm="zypper"
            install_cmd="sudo zypper install"
            pkg_map=(
                [kscreen-doctor]="kscreen"
                [sqlite3]="sqlite3"
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
    fi

    if [[ ${#manual[@]} -gt 0 ]]; then
        echo "" >&2
        echo "kdotool is not available in standard package repos." >&2
        echo "Install from source: https://github.com/jinliu/kdotool" >&2
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