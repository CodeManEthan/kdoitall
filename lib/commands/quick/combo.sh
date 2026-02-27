#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_QUICK_COMBO_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"

_quick_action_combo_move() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_combo_move"
    local input=""
    local new_desktop=""
    local new_screen=""
    local new_position=""

    debug_function_enter "$function_name" "$@"

    # Display combo move instructions
    echo "" >&3
    echo "Combo move — enter values separated by spaces." >&3
    echo "Format: <desktop> <screen> <position>" >&3
    echo "Use '.' to skip a value (keep current)." >&3
    echo "" >&3
    echo "Example: 2 1 rh    (desktop 2, screen 1, right half)" >&3
    echo "Example: . 2 fs     (keep desktop, screen 2, fullscreen)" >&3
    echo "Example: 3 . .      (desktop 3, keep screen, keep position)" >&3
    echo "" >&3

    # Read combo input
    read -r -p "Enter combo: " input

    if [[ -z "$input" ]]; then
        print_error "No input provided."
        debug_function_exit "$function_name"
        return 1
    fi

    # Parse space-separated values
    local -a parts=()
    read -ra parts <<< "$input"

    local raw_desktop="${parts[0]:-.}"
    local raw_screen="${parts[1]:-.}"
    local raw_position="${parts[2]:-.}"

    debug_log "$function_name" "Parsed combo: desktop='$raw_desktop' screen='$raw_screen' position='$raw_position'"

    # ── Validate desktop ──
    if [[ "$raw_desktop" != "." ]]; then
        if ! validate_desktop_number "$raw_desktop" > /dev/null 2>&1; then
            print_error "Invalid desktop '${raw_desktop}' (must be 1-${DETECTED_DESKTOP_COUNT})"
            debug_function_exit "$function_name"
            return 1
        fi
        new_desktop="$raw_desktop"
    fi

    # ── Validate screen ──
    local target_screen_output=""
    if [[ "$raw_screen" != "." ]]; then
        target_screen_output=$(resolve_screen_reference "$raw_screen") || true
        if [[ -z "$target_screen_output" ]]; then
            print_error "Invalid screen reference '${raw_screen}'"
            debug_function_exit "$function_name"
            return 1
        fi
        new_screen="$target_screen_output"
    fi

    # ── Validate position ──
    if [[ "$raw_position" != "." ]]; then
        new_position=$(resolve_position "$raw_position") || true
        if [[ -z "$new_position" ]]; then
            print_error "Invalid position '${raw_position}'"
            debug_function_exit "$function_name"
            return 1
        fi
    fi

    # Must have at least one non-skip value
    if [[ -z "$new_desktop" && -z "$new_screen" && -z "$new_position" ]]; then
        print_info "All values skipped — nothing to do."
        debug_function_exit "$function_name"
        return 0
    fi

    # ── Execute desktop move ──
    if [[ -n "$new_desktop" ]]; then
        move_window_to_desktop "$uuid" "$new_desktop"
        debug_log "$function_name" "Moved to desktop $new_desktop"
    fi

    # ── Determine current screen for position operations ──
    local current_screen=""
    if [[ -n "$new_screen" || -n "$new_position" ]]; then
        current_screen=$(detect_window_screen "$uuid") || true
        if [[ -z "$current_screen" ]]; then
            print_error "Could not detect which screen this window is on."
            debug_function_exit "$function_name"
            return 1
        fi
    fi

    # ── Execute screen + position move ──
    if [[ -n "$new_screen" && -n "$new_position" ]]; then
        # Both specified: move to screen then apply position
        move_window_to_screen "$uuid" "$new_screen"
        move_window_to_position "$uuid" "$new_screen" "$new_position"
        debug_log "$function_name" "Moved to screen $new_screen at '$new_position'"

    elif [[ -n "$new_screen" ]]; then
        # Screen only: preserve current position
        _quick_move_to_screen_with_position "$uuid" "$current_screen" "$new_screen"
        debug_log "$function_name" "Moved to screen $new_screen with position preserved"

    elif [[ -n "$new_position" ]]; then
        # Position only: apply on current screen
        move_window_to_position "$uuid" "$current_screen" "$new_position"
        debug_log "$function_name" "Repositioned to '$new_position' on screen $current_screen"
    fi

    # ── Confirmation ──
    local msg=""
    msg="Moved ${display_name}:"
    if [[ -n "$new_desktop" ]]; then
        msg+=" Desktop ${new_desktop}"
    fi
    if [[ -n "$new_screen" ]]; then
        msg+=" Screen ${new_screen}"
    fi
    if [[ -n "$new_position" ]]; then
        msg+=" ${new_position}"
    fi
    print_success "$msg"

    debug_function_exit "$function_name"
}
