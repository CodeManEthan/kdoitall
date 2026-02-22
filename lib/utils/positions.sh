#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

load_extra_positions() {
    # If EXTRA_POSITIONS is not defined or empty, nothing to do
    if ! [[ -v EXTRA_POSITIONS ]] || [[ ${#EXTRA_POSITIONS[@]} -eq 0 ]]; then
        return 0
    fi

    # Map display names to variable names and abbreviations
    local -A optional_position_map=(
        ["Left Two-Thirds"]="LEFTTWOTHIRDS:l2t"
        ["Right Two-Thirds"]="RIGHTTWOTHIRDS:r2t"
        ["Left 60"]="LEFT60:l60"
        ["Right 40"]="RIGHT40:r40"
        ["Left 40"]="LEFT40:l40"
        ["Right 60"]="RIGHT60:r60"
        ["Center Half"]="CENTERHALF:ch"
        ["Left 25"]="LEFT25:l25"
        ["Right 25"]="RIGHT25:r25"
        ["Center Two-Thirds"]="CENTERTWOTHIRDS:c2t"
        ["Top Two-Thirds"]="TOPTWOTHIRDS:t2t"
        ["Bottom Two-Thirds"]="BOTTOMTWOTHIRDS:b2t"
        ["Top 60"]="TOP60:t60"
        ["Bottom 40"]="BOTTOM40:b40"
        ["Top 40"]="TOP40:t40"
        ["Bottom 60"]="BOTTOM60:b60"
    )

    local next_index=""
    next_index=$((${#POSITION_MENU_ORDER[@]} + 1))
    local display_name=""
    local var_and_abbrev=""
    local var_name=""
    local abbrev=""

    for display_name in "${EXTRA_POSITIONS[@]}"; do
        if [[ -v optional_position_map[$display_name] ]]; then
            var_and_abbrev="${optional_position_map[$display_name]}"
            var_name="${var_and_abbrev%%:*}"
            abbrev="${var_and_abbrev##*:}"

            # shellcheck disable=SC2034
            POSITION_MENU[$next_index]="$var_name"
            POSITION_MENU_ORDER+=("$var_name")
            # shellcheck disable=SC2034
            POSITION_ABBREVIATIONS["$abbrev"]="$var_name"
            ((next_index++)) || true
        else
            echo "Warning: Unknown extra position '$display_name' — skipping" >&2
        fi
    done
}