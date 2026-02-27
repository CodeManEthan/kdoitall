#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_QUICK_ACTIONS_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"

quick_show_actions() {
    local uuid="$1"
    local display_name="$2"
    local window_title="$3"
    local location="$4"
    local function_name="quick_show_actions"
    local action=""

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Display selected window summary
    echo "" >&3
    print_info "Selected: ${display_name} — \"${window_title}\" (${location})"
    echo "" >&3

    # Display action menu
    echo "  1. Move to desktop" >&3
    echo "  2. Move to screen" >&3
    echo "  3. Move to position" >&3
    echo "  4. Combo move (desktop + screen + position)" >&3
    echo "  5. Focus" >&3
    echo "  6. Minimize" >&3
    echo "  7. Close" >&3
    echo "" >&3

    # Prompt for action selection
    while true; do
        read -r -p "Select action [1-7] (b to go back, q to quit): " action

        case "$action" in
            b|B)
                debug_function_exit "$function_name"
                # Return 2 signals "go back to picker"
                return 2
                ;;
            q|Q)
                debug_function_exit "$function_name"
                return 1
                ;;
            1)
                _quick_action_move_desktop "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            2)
                _quick_action_move_screen "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            3)
                _quick_action_move_position "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            4)
                _quick_action_combo_move "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            5)
                _quick_action_focus "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            6)
                _quick_action_minimize "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            7)
                _quick_action_close "$uuid" "$display_name"
                debug_function_exit "$function_name"
                return 0
                ;;
            *)
                print_error "Invalid selection. Enter a number between 1 and 7."
                continue
                ;;
        esac
    done
}

_quick_action_focus() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_focus"

    debug_function_enter "$function_name" "$@"

    kdotool activate_window "$uuid"
    print_success "Focused: ${display_name}"

    debug_function_exit "$function_name"
}

_quick_action_minimize() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_minimize"

    debug_function_enter "$function_name" "$@"

    kdotool minimize_window "$uuid"
    print_success "Minimized: ${display_name}"

    debug_function_exit "$function_name"
}

_quick_action_close() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_close"
    local window_name=""

    debug_function_enter "$function_name" "$@"

    # Look up window_name from uuid for DB cleanup
    window_name=$(db_get_window_name "$uuid") || true

    kdotool close_window "$uuid"

    # Remove from tracking if we found the window_name
    if [[ -n "$window_name" ]]; then
        db_delete_window "$window_name"
    fi

    print_success "Closed: ${display_name}"

    debug_function_exit "$function_name"
}

_quick_action_move_desktop() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_move_desktop"
    local current_desktop=""
    local selection=""
    local i=""

    debug_function_enter "$function_name" "$@"

    # Get current desktop for this window
    current_desktop=$(kdotool get_desktop_for_window "$uuid" 2>/dev/null) || true

    # Display available desktops
    echo "" >&3
    echo "Available Desktops:" >&3
    local marker=""
    for ((i = 1; i <= DETECTED_DESKTOP_COUNT; i++)); do
        marker=""
        if [[ "$i" == "$current_desktop" ]]; then
            marker="  ← current"
        fi
        echo "  ${i}. Desktop ${i}${marker}" >&3
    done
    echo "" >&3

    # Prompt for desktop selection
    while true; do
        read -r -p "Select desktop [1-${DETECTED_DESKTOP_COUNT}]: " selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "$DETECTED_DESKTOP_COUNT" ]]; then
            break
        fi

        print_error "Invalid selection. Enter a number between 1 and ${DETECTED_DESKTOP_COUNT}."
    done

    move_window_to_desktop "$uuid" "$selection"
    print_success "Moved ${display_name} to Desktop ${selection}"

    debug_function_exit "$function_name"
}

_quick_action_move_screen() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_move_screen"
    local current_screen=""
    local selection=""
    local out=""
    local screen_index=""
    local target_output=""

    debug_function_enter "$function_name" "$@"

    # Get current screen for this window
    current_screen=$(detect_window_screen "$uuid") || true

    # Display available screens
    echo "" >&3
    echo "Available Screens:" >&3

    # Build an indexed list from SCREEN_OUTPUT_IDS
    local -a screen_list=()
    local name=""
    local width=""
    local height=""
    local marker=""
    screen_index=0
    for out in "${SCREEN_OUTPUT_IDS[@]}"; do
        if [[ "$(get_screen_info "$out" "ENABLED")" != "true" ]]; then
            continue
        fi

        screen_index=$((screen_index + 1))
        screen_list+=("$out")

        name=$(get_screen_info "$out" "NAME")
        width=$(get_screen_info "$out" "WIDTH")
        height=$(get_screen_info "$out" "HEIGHT")

        marker=""
        if [[ "$out" == "$current_screen" ]]; then
            marker="  ← current"
        fi

        echo "  ${screen_index}. Screen ${out} (${name}, ${width}x${height})${marker}" >&3
    done
    echo "" >&3

    local screen_count=""
    screen_count=${#screen_list[@]}

    # Prompt for screen selection
    while true; do
        read -r -p "Select screen [1-${screen_count}]: " selection

        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "$screen_count" ]]; then
            break
        fi

        print_error "Invalid selection. Enter a number between 1 and ${screen_count}."
    done

    target_output="${screen_list[$((selection - 1))]}"

    # Position preservation: detect current position and reapply on new screen
    _quick_move_to_screen_with_position "$uuid" "$current_screen" "$target_output"

    print_success "Moved ${display_name} to Screen ${target_output}"

    debug_function_exit "$function_name"
}

_quick_move_to_screen_with_position() {
    local uuid="$1"
    local current_screen="$2"
    local target_screen="$3"
    local function_name="_quick_move_to_screen_with_position"
    local detected_position=""

    debug_function_enter "$function_name" "$@"

    # Try to detect current position for preservation
    if [[ -n "$current_screen" ]]; then
        detected_position=$(detect_window_position "$uuid" "$current_screen") || true
    fi

    if [[ -n "$detected_position" ]]; then
        # Known position — move to screen and reapply position
        move_window_to_screen "$uuid" "$target_screen"
        move_window_to_position "$uuid" "$target_screen" "$detected_position"
        debug_log "$function_name" "Preserved position '$detected_position' on screen $target_screen"
    else
        # Relative offset fallback — preserve geometry proportionally
        local win_pos=""
        local win_sz=""
        win_pos=$(get_window_position "$uuid")
        win_sz=$(get_window_size "$uuid")

        local win_x="${win_pos%,*}"
        local win_y="${win_pos#*,}"
        local win_w="${win_sz%x*}"
        local win_h="${win_sz#*x}"

        local old_sx=""
        local old_sy=""
        old_sx=$(get_screen_info "$current_screen" "X")
        old_sy=$(get_screen_info "$current_screen" "Y")

        local rel_x=$((win_x - old_sx))
        local rel_y=$((win_y - old_sy))

        local new_sx=""
        local new_sy=""
        local new_sw=""
        local new_sh=""
        new_sx=$(get_screen_info "$target_screen" "X")
        new_sy=$(get_screen_info "$target_screen" "Y")
        new_sw=$(get_screen_info "$target_screen" "WIDTH")
        new_sh=$(get_screen_info "$target_screen" "HEIGHT")

        # Clamp to ensure window stays on-screen
        if (( rel_x + win_w > new_sw )); then
            rel_x=$((new_sw - win_w))
            if (( rel_x < 0 )); then rel_x=0; fi
        fi
        if (( rel_y + win_h > new_sh )); then
            rel_y=$((new_sh - win_h))
            if (( rel_y < 0 )); then rel_y=0; fi
        fi

        move_window "$uuid" $((new_sx + rel_x)) $((new_sy + rel_y))
        size_window "$uuid" "$win_w" "$win_h"
        debug_log "$function_name" "Moved via relative fallback to screen $target_screen"
    fi

    debug_function_exit "$function_name"
}

_quick_action_move_position() {
    local uuid="$1"
    local display_name="$2"
    local function_name="_quick_action_move_position"
    local current_screen=""
    local current_position=""
    local selection=""

    debug_function_enter "$function_name" "$@"

    # Detect current screen (needed for move_window_to_position)
    current_screen=$(detect_window_screen "$uuid") || true
    if [[ -z "$current_screen" ]]; then
        print_error "Could not detect which screen this window is on."
        debug_function_exit "$function_name"
        return 1
    fi

    # Detect current position for marking
    current_position=$(detect_window_position "$uuid" "$current_screen") || true

    # Display position menu in 3-column layout
    echo "" >&3
    echo "Positions:" >&3

    local pos_count=""
    pos_count=${#POSITION_MENU_ORDER[@]}
    local pos_index=""
    local pos_var=""
    local pos_value=""
    local abbrev=""
    local key=""
    local marker=""
    local label=""
    local num=""
    local -a labels=()

    # Build label strings for each position
    for pos_index in "${!POSITION_MENU_ORDER[@]}"; do
        pos_var="${POSITION_MENU_ORDER[$pos_index]}"
        pos_value="${!pos_var}"

        # Find abbreviation
        abbrev=""
        for key in "${!POSITION_ABBREVIATIONS[@]}"; do
            if [[ "${POSITION_ABBREVIATIONS[$key]}" == "$pos_var" ]]; then
                abbrev="$key"
                break
            fi
        done

        marker=""
        if [[ "$pos_value" == "$current_position" ]]; then
            marker=" *"
        fi

        num=$((pos_index + 1))
        if [[ -n "$abbrev" ]]; then
            label="${num}. ${pos_value} (${abbrev})${marker}"
        else
            label="${num}. ${pos_value}${marker}"
        fi
        labels+=("$label")
    done

    # Display in 3-column rows
    local row=""
    local col1=""
    local col2=""
    local col3=""
    for ((row = 0; row < pos_count; row += 3)); do
        col1="${labels[$row]:-}"
        col2="${labels[$((row + 1))]:-}"
        col3="${labels[$((row + 2))]:-}"
        printf "   %-26s %-26s %s\n" "$col1" "$col2" "$col3" >&3
    done

    if [[ -n "$current_position" ]]; then
        echo "  (* = current)" >&3
    fi
    echo "" >&3

    # Prompt for position selection (number or abbreviation)
    local resolved_position=""
    while true; do
        read -r -p "Select position [1-${pos_count}] or abbreviation: " selection

        # Try as a number first
        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "$pos_count" ]]; then
            pos_var="${POSITION_MENU_ORDER[$((selection - 1))]}"
            resolved_position="${!pos_var}"
            break
        fi

        # Try as abbreviation or full name
        resolved_position=$(resolve_position "$selection") || true
        if [[ -n "$resolved_position" ]]; then
            break
        fi

        print_error "Invalid selection. Enter a number, abbreviation, or position name."
    done

    move_window_to_position "$uuid" "$current_screen" "$resolved_position"
    print_success "Moved ${display_name} to ${resolved_position}"

    debug_function_exit "$function_name"
}
