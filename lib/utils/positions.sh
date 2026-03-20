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

resolve_position_reference() {
    local input="$1"
    local function_name="resolve_position_reference"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$input" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "position_input"
        debug_function_exit "$function_name"
        return 1
    fi

    # Tier 1: Check abbreviations (case-sensitive, e.g., "fs" -> "FULLSCREEN")
    if [[ -v POSITION_ABBREVIATIONS[$input] ]]; then
        debug_log "$function_name" "Tier 1: Abbreviation '$input' -> ${POSITION_ABBREVIATIONS[$input]}"
        debug_function_exit "$function_name"
        echo "${POSITION_ABBREVIATIONS[$input]}"
        return 0
    fi

    # Tier 2: Uppercase input and check if it matches a variable name in POSITION_MENU_ORDER
    local upper_input=""
    upper_input="${input^^}"
    local var_name=""
    for var_name in "${POSITION_MENU_ORDER[@]}"; do
        if [[ "$var_name" == "$upper_input" ]]; then
            debug_log "$function_name" "Tier 2: Variable name match '$input' -> $var_name"
            debug_function_exit "$function_name"
            echo "$var_name"
            return 0
        fi
    done

    # Tier 3: Compare display values case-insensitively (e.g., "Fullscreen" -> "FULLSCREEN")
    local lower_input=""
    lower_input="${input,,}"
    for var_name in "${POSITION_MENU_ORDER[@]}"; do
        local display_value=""
        display_value="${!var_name}"
        if [[ "${display_value,,}" == "$lower_input" ]]; then
            debug_log "$function_name" "Tier 3: Display value match '$input' -> $var_name"
            debug_function_exit "$function_name"
            echo "$var_name"
            return 0
        fi
    done

    debug_error "$function_name" "$ERR_INVALID_POSITION" "Position not found: $input"
    debug_function_exit "$function_name"
    return 1
}