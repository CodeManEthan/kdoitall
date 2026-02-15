#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Database location
export KDOITALL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"
export WORKSPACE_SCRIPTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/workspaces"
export KDOITALL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kdoitall/config"

readonly KDOITALL_DB WORKSPACE_SCRIPTS_DIR KDOITALL_CONFIG

# Timing delays
export LAUNCH_DELAY="1.0"
export WINDOW_DELAY="0.1"
export DESKTOP_DELAY="0.1"
export SCREEN_DELAY="0.1"
export POSITION_DELAY="0.5"
export KEYPRESS_DELAY="0.05"
export KEY_CHORD_DELAY="0.5"
export TYPE_TEXT_DELAY="0.1"

readonly LAUNCH_DELAY WINDOW_DELAY DESKTOP_DELAY SCREEN_DELAY POSITION_DELAY
readonly KEYPRESS_DELAY KEY_CHORD_DELAY TYPE_TEXT_DELAY

# Application launch modes
export LAUNCH_MODE_MULTI="multi"    # Multiple windows always allowed
export LAUNCH_MODE_SINGLE="single"  # Only one instance allowed
export LAUNCH_MODE_UNIQUE="unique"  # Multiple windows, but not the same
export LAUNCH_MODE_UNKNOWN="unknown"
export LAUNCH_MODE_SINGLE_OR_UNIQUE="single_or_unique"  # Not multi, but unknown if single or unique

readonly LAUNCH_MODE_MULTI LAUNCH_MODE_SINGLE LAUNCH_MODE_UNIQUE LAUNCH_MODE_UNKNOWN LAUNCH_MODE_SINGLE_OR_UNIQUE

# Application launch types
export LAUNCH_TYPE_TERMINAL="terminal"
export LAUNCH_TYPE_DESKTOP="desktop"

readonly LAUNCH_TYPE_TERMINAL LAUNCH_TYPE_DESKTOP

# Window position modes
export FULLSCREEN="Fullscreen"
export RIGHTHALF="Right Half"
export LEFTHALF="Left Half"
export TOPHALF="Top Half"
export BOTTOMHALF="Bottom Half"
export TOPLEFT="Top Left"
export TOPRIGHT="Top Right"
export BOTTOMLEFT="Bottom Left"
export BOTTOMRIGHT="Bottom Right"
export LEFTTHIRD="Left Third"
export MIDDLETHIRD="Middle Third"
export RIGHTTHIRD="Right Third"

readonly FULLSCREEN
readonly RIGHTHALF LEFTHALF TOPHALF BOTTOMHALF 
readonly TOPLEFT TOPRIGHT BOTTOMLEFT BOTTOMRIGHT
readonly LEFTTHIRD MIDDLETHIRD RIGHTTHIRD

# In lib/core/common.sh
declare -gA POSITION_MENU=(
    [1]="FULLSCREEN"
    [2]="RIGHTHALF"
    [3]="LEFTHALF"
    [4]="TOPHALF"
    [5]="BOTTOMHALF"
    [6]="TOPLEFT"
    [7]="TOPRIGHT"
    [8]="BOTTOMLEFT"
    [9]="BOTTOMRIGHT"
    [10]="LEFTTHIRD"
    [11]="MIDDLETHIRD"
    [12]="RIGHTTHIRD"
)

declare -ga POSITION_MENU_ORDER=(
    "FULLSCREEN"
    "RIGHTHALF"
    "LEFTHALF"
    "TOPHALF"
    "BOTTOMHALF"
    "TOPLEFT"
    "TOPRIGHT"
    "BOTTOMLEFT"
    "BOTTOMRIGHT"
    "LEFTTHIRD"
    "MIDDLETHIRD"
    "RIGHTTHIRD"
)

# shellcheck disable=SC2034
readonly POSITION_MENU POSITION_MENU_ORDER
