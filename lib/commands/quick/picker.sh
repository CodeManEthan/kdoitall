#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_QUICK_PICKER_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"

# Global arrays populated by quick_show_picker for selection reference
QUICK_UUIDS=()
QUICK_CLASSES=()
QUICK_TITLES=()
QUICK_DISPLAY_NAMES=()
QUICK_WORKSPACE_NAMES=()
QUICK_APP_IDS=()
QUICK_LOCATIONS=()

quick_show_picker() {
    local function_name="quick_show_picker"
    local window_list=""
    local selection=""

    debug_function_enter "$function_name"

    # Reset arrays
    QUICK_UUIDS=()
    QUICK_CLASSES=()
    QUICK_TITLES=()
    QUICK_DISPLAY_NAMES=()
    QUICK_WORKSPACE_NAMES=()
    QUICK_APP_IDS=()
    QUICK_LOCATIONS=()

    # Get window list from database
    window_list=$(db_get_quick_window_list) || true

    if [[ -z "$window_list" ]]; then
        print_warning "No manageable windows found."
        debug_function_exit "$function_name"
        return 1
    fi

    # Parse results into arrays
    local uuid=""
    local class=""
    local window_title=""
    local display_name=""
    local workspace_name=""
    local app_id=""

    while IFS='|' read -r uuid class window_title display_name workspace_name app_id; do
        [[ -z "$uuid" ]] && continue

        # Display name fallback: capitalize first letter of raw class
        if [[ "$display_name" == "$class" ]]; then
            display_name="${class^}"
        fi

        QUICK_UUIDS+=("$uuid")
        QUICK_CLASSES+=("$class")
        QUICK_TITLES+=("$window_title")
        QUICK_DISPLAY_NAMES+=("$display_name")
        QUICK_WORKSPACE_NAMES+=("$workspace_name")
        QUICK_APP_IDS+=("$app_id")
    done <<< "$window_list"

    local count=""
    count=${#QUICK_UUIDS[@]}

    if [[ "$count" -eq 0 ]]; then
        print_warning "No manageable windows found."
        debug_function_exit "$function_name"
        return 1
    fi

    # Gather live location data for each window
    local loc_uuid=""
    local loc_desktop=""
    local loc_screen=""
    local loc_position=""
    local loc_str=""
    local loc_i=""
    for loc_i in "${!QUICK_UUIDS[@]}"; do
        loc_uuid="${QUICK_UUIDS[$loc_i]}"

        loc_desktop=$(kdotool get_desktop_for_window "$loc_uuid" 2>/dev/null) || true
        loc_screen=$(detect_window_screen "$loc_uuid") || true

        loc_position=""
        if [[ -n "$loc_screen" ]]; then
            loc_position=$(detect_window_position "$loc_uuid" "$loc_screen") || true
        fi

        loc_str="D${loc_desktop:-?} S${loc_screen:-?}"
        if [[ -n "$loc_position" ]]; then
            loc_str+=" ${loc_position}"
        else
            loc_str+=" (custom pos)"
        fi

        QUICK_LOCATIONS+=("$loc_str")
    done

    # Display header
    echo "" >&3
    print_header "Active Windows"
    printf "  %-4s %-18s %-14s %-35s %s\n" "#" "APP NAME" "CLASS" "TITLE" "LOCATION" >&3
    printf "  %-4s %-18s %-14s %-35s %s\n" \
        "$(printf '%.0s─' {1..3})" \
        "$(printf '%.0s─' {1..16})" \
        "$(printf '%.0s─' {1..12})" \
        "$(printf '%.0s─' {1..33})" \
        "$(printf '%.0s─' {1..20})" >&3

    # Display each window
    local i=""
    local num=""
    local name=""
    local cls=""
    local title=""
    local ws=""
    local loc=""
    for i in "${!QUICK_UUIDS[@]}"; do
        num=$((i + 1))
        name="${QUICK_DISPLAY_NAMES[$i]}"
        cls="${QUICK_CLASSES[$i]}"
        title="${QUICK_TITLES[$i]}"
        ws="${QUICK_WORKSPACE_NAMES[$i]}"
        loc="${QUICK_LOCATIONS[$i]}"

        # Workspace annotation for non-auto windows
        if [[ "$ws" != "~workspace" && -n "$ws" ]]; then
            title="[ws]${ws} ${title}"
        fi

        # Truncate title to 33 characters
        if [[ ${#title} -gt 33 ]]; then
            title="${title:0:30}..."
        fi

        # Truncate display name to 18 characters
        if [[ ${#name} -gt 18 ]]; then
            name="${name:0:15}..."
        fi

        # Truncate class to 14 characters
        if [[ ${#cls} -gt 14 ]]; then
            cls="${cls:0:11}..."
        fi

        printf "  %-4s %-18s %-14s %-35s %s\n" "$num" "$name" "$cls" "$title" "$loc" >&3
    done

    echo "" >&3

    # Prompt for selection
    while true; do
        read -r -p "Select window [1-${count}] (q to quit): " selection

        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            debug_function_exit "$function_name"
            return 1
        fi

        # Validate numeric input in range
        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "$count" ]]; then
            QUICK_SELECTED_INDEX=$((selection - 1))
            debug_log "$function_name" "Selected window index: $QUICK_SELECTED_INDEX (${QUICK_DISPLAY_NAMES[$QUICK_SELECTED_INDEX]})"
            debug_function_exit "$function_name"
            return 0
        fi

        print_error "Invalid selection. Enter a number between 1 and ${count}."
    done
}
