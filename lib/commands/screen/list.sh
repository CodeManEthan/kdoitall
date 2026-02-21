#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SCREEN_LIST_LOADED" || return 0

# shellcheck source=../../db/screen.sh
source "${LIB_DIR}/db/screen.sh"

screen_list() {
    local function_name="screen_list"
    local out=""

    debug_function_enter "$function_name"

    if [[ $DETECTED_SCREEN_COUNT -eq 0 ]]; then
        echo "No screens detected." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    echo "Detected Screens: $DETECTED_SCREEN_COUNT" >&3
    echo "----------------------------------------" >&3

    for out in "${SCREEN_OUTPUT_IDS[@]}"; do
        if [[ "${SCREEN_INFO[${out}_ENABLED]}" == "true" ]]; then
            local name="${SCREEN_INFO[${out}_NAME]}"
            local width="${SCREEN_INFO[${out}_WIDTH]}"
            local height="${SCREEN_INFO[${out}_HEIGHT]}"
            local x="${SCREEN_INFO[${out}_X]}"
            local y="${SCREEN_INFO[${out}_Y]}"

            # Look up aliases that point to this screen's name
            local aliases=""
            aliases=$(db_get_aliases_for_target "$name")

            local alias_display=""
            if [[ -n "$aliases" ]]; then
                # Convert newline-separated list to comma-separated
                alias_display=$(echo "$aliases" | paste -sd ', ')
                alias_display=" (aliases: $alias_display)"
            else
                alias_display=" (no aliases)"
            fi

            echo "" >&3
            echo "Screen $out: ${name}${alias_display}" >&3
            echo "  Resolution: ${width}x${height}" >&3
            echo "  Position: ($x, $y)" >&3
        fi
    done

    echo "" >&3
    debug_function_exit "$function_name"
    return 0
}
