#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_UTILS_COLORS_LOADED" || return 0

# UI color constants - disabled if fd 3 is not a terminal or NO_COLOR is set
# Prefixed with UI_ to avoid colliding with debug.sh's COLOR_* variables,
# which target stderr and use their own TTY detection.
if [[ -t 3 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    UI_COLOR_RED='\033[0;31m'
    UI_COLOR_GREEN='\033[0;32m'
    UI_COLOR_YELLOW='\033[0;33m'
    UI_COLOR_CYAN='\033[0;36m'
    UI_COLOR_BOLD='\033[1m'
    UI_COLOR_DIM='\033[2m'
    UI_COLOR_RESET='\033[0m'
else
    UI_COLOR_RED=''
    UI_COLOR_GREEN=''
    UI_COLOR_YELLOW=''
    UI_COLOR_CYAN=''
    UI_COLOR_BOLD=''
    UI_COLOR_DIM=''
    UI_COLOR_RESET=''
fi

# --- Helper functions ---
# All output to fd 3 (user-facing output)

print_success() {
    echo -e "${UI_COLOR_GREEN}✓ $1${UI_COLOR_RESET}" >&3
}

print_error() {
    echo -e "${UI_COLOR_RED}✗ $1${UI_COLOR_RESET}" >&3
}

print_warning() {
    echo -e "${UI_COLOR_YELLOW}⚠ $1${UI_COLOR_RESET}" >&3
}

print_header() {
    echo -e "${UI_COLOR_BOLD}${UI_COLOR_CYAN}=== $1 ===${UI_COLOR_RESET}" >&3
}

print_banner() {
    echo -e "${UI_COLOR_BOLD}${UI_COLOR_GREEN}================================================================${UI_COLOR_RESET}" >&3
    echo -e "${UI_COLOR_BOLD}${UI_COLOR_GREEN}$1${UI_COLOR_RESET}" >&3
    echo -e "${UI_COLOR_BOLD}${UI_COLOR_GREEN}================================================================${UI_COLOR_RESET}" >&3
}

print_prompt() {
    echo -e "${UI_COLOR_BOLD}${UI_COLOR_YELLOW}$1${UI_COLOR_RESET}" >&3
}

print_info() {
    echo -e "${UI_COLOR_DIM}$1${UI_COLOR_RESET}" >&3
}

print_step() {
    echo -e "${UI_COLOR_BOLD}${UI_COLOR_CYAN}$1${UI_COLOR_RESET}" >&3
    echo -e "${UI_COLOR_CYAN}$(printf '%0.s-' $(seq 1 ${#1}))${UI_COLOR_RESET}" >&3
}
