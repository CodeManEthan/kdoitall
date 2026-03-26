#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_NAME_LOADED" || return 0

# Restricted names that auto-generation must avoid.
# These are structural components of reverse-DNS identifiers or
# too generic to be meaningful. Only applies to auto-generation —
# users can manually set any name via `app name`.
readonly -a APPNAME_RESTRICTED_NAMES=(
    # TLD / domain segments
    com org net io dev app me de uk eu
    # Common structural segments
    desktop client gtk qt qt5 qt6
    # Overly generic names
    settings preferences config configuration
    manager editor viewer launcher helper
)

appname_is_restricted() {
    local name="$1"
    local restricted=""
    for restricted in "${APPNAME_RESTRICTED_NAMES[@]}"; do
        [[ "$name" == "$restricted" ]] && return 0
    done
    return 1
}

# Find the longest common substring between two strings (case-insensitive).
# Returns the match on stdout, or empty string if no match >= 3 chars.
appname_longest_common_substring() {
    local str1="${1,,}"
    local str2="${2,,}"
    local len1=${#str1}
    local best=""
    local best_len=2

    local start end substr remaining
    for ((start = 0; start < len1; start++)); do
        remaining=$((len1 - start))
        [[ $remaining -le $best_len ]] && break

        for ((end = len1; end > start + best_len; end--)); do
            substr="${str1:start:end-start}"
            if [[ "$str2" == *"$substr"* ]]; then
                best="$substr"
                best_len=${#best}
                break
            fi
        done
    done

    echo "$best"
}

# Generate a candidate app_name from app_id and display_name.
# Implements Steps 1-3 of the name generation algorithm.
appname_generate() {
    local app_id="$1"
    local display_name="$2"
    local function_name="appname_generate"

    debug_function_enter "$function_name" "$@"

    # Step 1: Split app_id on dots to get segments
    local -a segments=()
    IFS='.' read -ra segments <<< "$app_id"

    local last_segment="${segments[-1]}"
    local last_lower="${last_segment,,}"

    # Step 2: Find common substring between last segment and display name
    local display_lower="${display_name,,}"
    local match=""
    match=$(appname_longest_common_substring "$last_lower" "$display_lower")

    if [[ -n "$match" ]] && ! appname_is_restricted "$match"; then
        debug_log "$function_name" "Common substring match: '$match' for $app_id"
        debug_function_exit "$function_name"
        echo "$match"
        return 0
    fi

    # Step 3: Fallback chain
    # 3a: Use last segment (lowercased)
    if ! appname_is_restricted "$last_lower"; then
        debug_log "$function_name" "Using last segment: '$last_lower' for $app_id"
        debug_function_exit "$function_name"
        echo "$last_lower"
        return 0
    fi

    # 3b: Last segment is restricted — combine second-to-last + last
    if [[ ${#segments[@]} -ge 2 ]]; then
        local second_to_last="${segments[-2],,}"
        local combined="${second_to_last}-${last_lower}"
        debug_log "$function_name" "Combined fallback: '$combined' for $app_id"
        debug_function_exit "$function_name"
        echo "$combined"
        return 0
    fi

    # 3c: No dots — use full app_id directly (lowercased)
    local result="${app_id,,}"
    debug_log "$function_name" "Using full app_id: '$result'"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# Deduplicate candidate app names in place.
# Takes parallel arrays by reference:
#   $1 = app_ids[]        (read-only)
#   $2 = candidate_names[] (modified in place)
#   $3 = locked[]          (read-only; "true" = skip)
#   $4 = display_names[]   (read-only)
appname_deduplicate() {
    local -n _appname_ids=$1
    local -n _appname_names=$2
    local -n _appname_locked=$3
    local -n _appname_displays=$4
    local function_name="appname_deduplicate"

    debug_function_enter "$function_name"

    local max_rounds=3
    local round=0

    while [[ $round -lt $max_rounds ]]; do
        ((round++))

        # Build name → indices map (unlocked entries only)
        local -A _appname_groups=()
        local _appname_i
        for _appname_i in "${!_appname_ids[@]}"; do
            [[ "${_appname_locked[$_appname_i]}" == "true" ]] && continue
            local _appname_key="${_appname_names[$_appname_i]}"
            if [[ -v _appname_groups[$_appname_key] ]]; then
                _appname_groups[$_appname_key]+=" $_appname_i"
            else
                _appname_groups[$_appname_key]="$_appname_i"
            fi
        done

        # Build set of locked names for conflict detection
        local -A _appname_locked_set=()
        for _appname_i in "${!_appname_ids[@]}"; do
            [[ "${_appname_locked[$_appname_i]}" == "true" ]] && \
                _appname_locked_set[${_appname_names[$_appname_i]}]=1
        done

        local _appname_had_conflicts=false

        local _appname_gname
        for _appname_gname in "${!_appname_groups[@]}"; do
            local _appname_indices="${_appname_groups[$_appname_gname]}"
            local -a _appname_idx_arr=($_appname_indices)

            # Conflict: >1 unlocked apps share name, or conflicts with locked name
            local _appname_locked_conflict=false
            [[ -v _appname_locked_set[$_appname_gname] ]] && _appname_locked_conflict=true

            if [[ ${#_appname_idx_arr[@]} -le 1 ]] && [[ "$_appname_locked_conflict" == "false" ]]; then
                continue
            fi

            _appname_had_conflicts=true
            debug_log "$function_name" "Duplicate '$_appname_gname': ${#_appname_idx_arr[@]} app(s) (round $round)"

            _appname_resolve_group "$1" "$2" "$4" _appname_idx_arr "$_appname_gname" "$round"
        done

        # Clean up associative arrays before next iteration
        unset _appname_groups _appname_locked_set

        [[ "$_appname_had_conflicts" == "false" ]] && break
    done

    debug_function_exit "$function_name"
}

# Internal: resolve a group of apps sharing the same candidate name.
# Called once per round per duplicate group.
_appname_resolve_group() {
    local -n __resolve_ids=$1
    local -n __resolve_names=$2
    local -n __resolve_displays=$3
    local -n __resolve_indices=$4
    local duplicate_name="$5"
    local round="$6"

    case "$round" in
        1)
            # Round 1: Use last segment (if different from candidate) or full app_id for no-dots
            local idx
            for idx in "${__resolve_indices[@]}"; do
                local app_id="${__resolve_ids[$idx]}"
                local -a segs=()
                IFS='.' read -ra segs <<< "$app_id"

                if [[ ${#segs[@]} -le 1 ]]; then
                    # No dots: use full app_id as name
                    __resolve_names[$idx]="${app_id,,}"
                elif [[ "${segs[-1],,}" != "$duplicate_name" ]]; then
                    # Last segment differs from candidate — use it directly
                    __resolve_names[$idx]="${segs[-1],,}"
                fi
            done
            ;;
        2)
            # Round 2: Display name differentiation, then namespace prefix
            # Collect display name words across the group
            local -A _resolve_word_counts=()
            local -A _resolve_app_words=()
            local idx
            for idx in "${__resolve_indices[@]}"; do
                [[ "${__resolve_names[$idx]}" != "$duplicate_name" ]] && continue
                local display="${__resolve_displays[$idx],,}"
                local -a words=()
                read -ra words <<< "${display//[-_]/ }"
                local word
                for word in "${words[@]}"; do
                    [[ ${#word} -ge 3 ]] || continue
                    _resolve_word_counts[$word]=$(( ${_resolve_word_counts[$word]:-0} + 1 ))
                    _resolve_app_words["$idx:$word"]=1
                done
            done

            for idx in "${__resolve_indices[@]}"; do
                [[ "${__resolve_names[$idx]}" != "$duplicate_name" ]] && continue

                local app_id="${__resolve_ids[$idx]}"
                local -a segs=()
                IFS='.' read -ra segs <<< "$app_id"

                # Try display name differentiation: find a unique word
                local resolved=false
                local display="${__resolve_displays[$idx],,}"
                local -a words=()
                read -ra words <<< "${display//[-_]/ }"
                local word
                for word in "${words[@]}"; do
                    [[ ${#word} -ge 3 ]] || continue
                    [[ "$word" == "$duplicate_name" ]] && continue
                    if [[ "${_resolve_word_counts[$word]:-0}" -eq 1 ]]; then
                        __resolve_names[$idx]="${duplicate_name}-${word}"
                        resolved=true
                        break
                    fi
                done
                [[ "$resolved" == "true" ]] && continue

                # Fallback: prepend namespace (second-to-last segment)
                if [[ ${#segs[@]} -ge 2 ]]; then
                    __resolve_names[$idx]="${segs[-2],,}-${segs[-1],,}"
                fi
            done

            unset _resolve_word_counts _resolve_app_words
            ;;
        3)
            # Round 3: Last resort — full app_id with dots replaced by hyphens
            local idx
            for idx in "${__resolve_indices[@]}"; do
                [[ "${__resolve_names[$idx]}" != "$duplicate_name" ]] && continue
                local app_id="${__resolve_ids[$idx]}"
                local full_name="${app_id//\./-}"
                __resolve_names[$idx]="${full_name,,}"
            done
            ;;
    esac
}
