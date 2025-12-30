#!/bin/bash

# Database location
export KDOITALL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"
export KDOITALL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kdoitall/config"

readonly KDOITALL_DB KDOITALL_CONFIG

# Workspace scripts location
export WORKSPACE_DIR="$HOME/.local/bin"

readonly WORKSPACE_DIR

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

readonly LAUNCH_MODE_MULTI LAUNCH_MODE_SINGLE LAUNCH_MODE_UNIQUE

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
