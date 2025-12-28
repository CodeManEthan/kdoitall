#!/bin/bash

# Database location
export KDOITALL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"
export KDOITALL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kdoitall/config"

readonly KDOITALL_DB KDOITALL_CONFIG

# Workspace scripts location
export WORKSPACE_DIR="$HOME/.local/bin"

readonly WORKSPACE_DIR

# OS Setup
export NUM_DESKTOPS="9"
export NUM_SCREENS="2"

readonly NUM_DESKTOPS NUM_SCREENS

# Screen sizes (make these configurable later)
export SCREEN1_SIZE="1920x1036"
export SCREEN2_SIZE="1920x1080"
export SCREEN3_SIZE=""
export SCREEN4_SIZE=""
export SCREEN5_SIZE=""
export SCREEN6_SIZE=""
export SCREEN7_SIZE=""
export SCREEN8_SIZE=""
export SCREEN9_SIZE=""
export SCREEN10_SIZE=""

readonly SCREEN1_SIZE SCREEN2_SIZE SCREEN3_SIZE SCREEN4_SIZE SCREEN5_SIZE
readonly SCREEN6_SIZE SCREEN7_SIZE SCREEN8_SIZE SCREEN9_SIZE SCREEN10_SIZE

# Timing delays
export LAUNCH_DELAY="1.0"
export WINDOW_DELAY="0.5"
export DESKTOP_DELAY="0.5"
export SCREEN_DELAY="0.5"
export POSITION_DELAY="0.5"
export KEYPRESS_DELAY="0.05"
export KEY_CHORD_DELAY="0.1"
export TYPE_TEXT_DELAY="0.1"

readonly LAUNCH_DELAY WINDOW_DELAY DESKTOP_DELAY SCREEN_DELAY POSITION_DELAY
readonly KEYPRESS_DELAY KEY_CHORD_DELAY TYPE_TEXT_DELAY

# Window launch modes
export LAUNCH_MODE_MULTI="multi"    # Multiple windows always allowed
export LAUNCH_MODE_SINGLE="single"  # Only one instance allowed
export LAUNCH_MODE_UNIQUE="unique"  # Multiple windows, but not with same path

readonly LAUNCH_MODE_MULTI LAUNCH_MODE_SINGLE LAUNCH_MODE_UNIQUE

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

# Screen Shortcut Keys
export MOVE_TO_SCREEN_MODIFIER="super + ctrl"
export MOVE_WINDOW_TO_SCREEN_MODIFIER="super + ctrl + shift"

export SCREEN1_KEY="1"
export SCREEN2_KEY="2"
export SCREEN3_KEY="3"
export SCREEN4_KEY="4"
export SCREEN5_KEY="5"
export SCREEN6_KEY="6"
export SCREEN7_KEY="7"
export SCREEN8_KEY="8"
export SCREEN9_KEY="9"
export SCREEN10_KEY="10"

readonly MOVE_TO_SCREEN_MODIFIER MOVE_WINDOW_TO_SCREEN_MODIFIER
readonly SCREEN1_KEY SCREEN2_KEY SCREEN3_KEY SCREEN4_KEY SCREEN5_KEY
readonly SCREEN6_KEY SCREEN7_KEY SCREEN8_KEY SCREEN9_KEY SCREEN10_KEY
