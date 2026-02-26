#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_UTILS_COLORS_LOADED" || return 0

# Color constants - disabled if fd 3 is not a terminal or NO_COLOR is set
if [[ -t 3 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_CYAN='\033[0;36m'
    COLOR_BOLD='\033[1m'
    COLOR_DIM='\033[2m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_CYAN=''
    COLOR_BOLD=''
    COLOR_DIM=''
    COLOR_RESET=''
fi

# --- Helper functions ---
# All output to fd 3 (user-facing output)

print_success() {
    echo -e "${COLOR_GREEN}✓ $1${COLOR_RESET}" >&3
}

print_error() {
    echo -e "${COLOR_RED}✗ $1${COLOR_RESET}" >&3
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠ $1${COLOR_RESET}" >&3
}

print_header() {
    echo -e "${COLOR_BOLD}${COLOR_CYAN}=== $1 ===${COLOR_RESET}" >&3
}

print_banner() {
    echo -e "${COLOR_BOLD}${COLOR_GREEN}================================================================${COLOR_RESET}" >&3
    echo -e "${COLOR_BOLD}${COLOR_GREEN}$1${COLOR_RESET}" >&3
    echo -e "${COLOR_BOLD}${COLOR_GREEN}================================================================${COLOR_RESET}" >&3
}

print_prompt() {
    echo -e "${COLOR_BOLD}$1${COLOR_RESET}" >&3
}

print_info() {
    echo -e "${COLOR_DIM}$1${COLOR_RESET}" >&3
}

print_step() {
    echo -e "${COLOR_BOLD}${COLOR_CYAN}$1${COLOR_RESET}" >&3
    echo -e "${COLOR_CYAN}$(printf '%0.s-' $(seq 1 ${#1}))${COLOR_RESET}" >&3
}
