#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

# Common key codes
declare -A KEYS=(
    # Modifiers
    [ctrl]=29
    [shift]=42
    [alt]=56
    [super]=125
    [capslock]=58
    
    # Special keys
    [enter]=28
    [esc]=1
    [backspace]=14
    [tab]=15
    [space]=57
    
    # Arrow keys
    [left]=105
    [right]=106
    [up]=103
    [down]=108
    
    # Navigation
    [home]=102
    [end]=107
    [pageup]=104
    [pagedown]=109
    [delete]=111
    [insert]=110
    
    # Function keys
    [f1]=59 [f2]=60 [f3]=61 [f4]=62
    [f5]=63 [f6]=64 [f7]=65 [f8]=66
    [f9]=67 [f10]=68 [f11]=87 [f12]=88
    
    # Letters
    [a]=30 [b]=48 [c]=46 [d]=32 [e]=18 [f]=33
    [g]=34 [h]=35 [i]=23 [j]=36 [k]=37 [l]=38
    [m]=50 [n]=49 [o]=24 [p]=25 [q]=16 [r]=19
    [s]=31 [t]=20 [u]=22 [v]=47 [w]=17 [x]=45
    [y]=21 [z]=44
    
    # Numbers
    [1]=2 [2]=3 [3]=4 [4]=5 [5]=6
    [6]=7 [7]=8 [8]=9 [9]=10 [0]=11

    # Numpad keys
    [kp0]=82
    [kp1]=79
    [kp2]=80
    [kp3]=81
    [kp4]=75
    [kp5]=76
    [kp6]=77
    [kp7]=71
    [kp8]=72
    [kp9]=73
    [kpasterisk]=55
    [kpminus]=74
    [kpplus]=78
    [kpenter]=96
    [kpdot]=83
    [kpslash]=98
    
    # Symbols (top row)
    [minus]=12          # -
    [equal]=13          # =
    [leftbrace]=26      # [
    [rightbrace]=27     # ]
    [backslash]=43      # \
    [semicolon]=39      # ;
    [apostrophe]=40     # '
    [grave]=41          # `
    [comma]=51          # ,
    [dot]=52            # .
    [slash]=53          # /
)

# Cleanup tracker
declare -a PRESSED_KEYS=()

cleanup() {
    local function_name="cleanup"

    # Only run cleanup if there are actually keys pressed
    if [[ ${#PRESSED_KEYS[@]} -eq 0 ]]; then
        return
    fi

    debug_function_enter "$function_name"

    debug_log "$function_name" "CLEANUP: Starting cleanup, ${#PRESSED_KEYS[@]} keys pressed"

    # Release all tracked keys
    for key in "${PRESSED_KEYS[@]}"; do
        ydotool key "$key:0"
    done

    debug_function_exit "$function_name"
    exit
}

# Press a key (tracks it for cleanup)
press_key() {
    local key_name=$1
    local keycode=""
    local function_name="press_key"
    
    keycode=${KEYS[$key_name]}

    if [[ -z $keycode ]]; then
        debug_error "$function_name" "$ERR_UNKNOWN_KEY" "$key_name"
        return 1
    fi
    
    ydotool key "$keycode:1"
    PRESSED_KEYS+=("$keycode")
    sleep "$KEYPRESS_DELAY"
}

# Release a key (removes from tracking)
release_key() {
    local key_name=$1
    local keycode=""
    local function_name="release_key"

    keycode=${KEYS[$key_name]}
    
    if [[ -z $keycode ]]; then
        debug_error "$function_name" "$ERR_UNKNOWN_KEY" "$key_name"
        return 1
    fi
    
    ydotool key "$keycode:0"
    
    # Remove from tracked keys (proper array filtering)
    local new_keys=()
    for k in "${PRESSED_KEYS[@]}"; do
        if [[ "$k" != "$keycode" ]]; then
            new_keys+=("$k")
        fi
    done
    PRESSED_KEYS=("${new_keys[@]}")
    
    sleep "$KEYPRESS_DELAY"
}

# Press and release a key (complete keystroke)
tap_key() {
    local key_name=$1
    debug_log "TAP: $key_name"
    press_key "$key_name"
    release_key "$key_name"
}

# Press multiple keys together (chord)
chord() {
    local keys=("$@")
    local function_name="chord"

    debug_function_enter "$function_name" "$@"

    debug_chord "${keys[@]}"
    
    # Press all keys
    for key in "${keys[@]}"; do
        press_key "$key" || {
            # Release what we've pressed so far
            for ((i=${#keys[@]}-1; i>=0; i--)); do
                release_key "${keys[i]}" 2>/dev/null || true
            done
            return 1
        }
    done
    
    sleep 0.05  # Brief hold time
    
    # Release all keys in reverse order
    for ((i=${#keys[@]}-1; i>=0; i--)); do
        release_key "${keys[i]}"
    done
    
    # Add delay after chord completes
    sleep "$KEY_CHORD_DELAY"

    debug_function_exit "$function_name"
}

# Type text safely
type_text() {
    local function_name="type_text"

    debug_function_enter "$function_name" "$@"

    debug_log "$function_name" "TYPE: '$1'"
    ydotool type "$1"
    sleep "$TYPE_TEXT_DELAY"

    debug_function_exit "$function_name"
}

# Setup trap
trap cleanup EXIT INT TERM
