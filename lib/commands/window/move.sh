#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_MOVE_LOADED" || return 0

# shellcheck source=../../core/core.sh
source "${LIB_DIR}/core/core.sh"

window_move_show_help() {
    cat << 'EOF' >&3
Usage: kdoitall window move <window-name> [options]

Positional mode (order: desktop, screen, position):
  kdoitall window move <name> <desktop>
  kdoitall window move <name> <desktop> <screen>
  kdoitall window move <name> <desktop> <screen> <position>

Flag mode (any combination, any order):
  kdoitall window move <name> --desktop <n>    (-d)
  kdoitall window move <name> --screen <ref>   (-s)
  kdoitall window move <name> --position <pos> (-p)

Unspecified properties are preserved. Only what you specify changes.

EOF
    window_move_show_positions
}

window_move_show_positions() {
    cat << 'EOF' >&3
Positions (full name or abbreviation):
  Fullscreen (fs)    Right Half (rh)    Left Half (lh)
  Top Half (th)      Bottom Half (bh)
  Top Left (tl)      Top Right (tr)
  Bottom Left (bl)   Bottom Right (br)
  Left Third (lt)    Middle Third (mt)  Right Third (rt)

EOF
}

window_move() {
    local function_name="window_move"
    local window_name=""
    local new_desktop=""
    local new_screen=""
    local new_position=""
    local flag_mode=false
    local -a positional_args=()

    debug_function_enter "$function_name" "$@"

    # ──────────────────────────────────────────────
    # STEP 1: Scan arguments — detect flag vs positional mode
    # ──────────────────────────────────────────────

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --desktop|-d)
                flag_mode=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    new_desktop="$2"
                    shift 2
                else
                    echo "Error: --desktop requires a value" >&3
                    debug_function_exit "$function_name"
                    return 1
                fi
                ;;
            --screen|-s)
                flag_mode=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    new_screen="$2"
                    shift 2
                else
                    echo "Error: --screen requires a value" >&3
                    debug_function_exit "$function_name"
                    return 1
                fi
                ;;
            --position|-p)
                flag_mode=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    new_position="$2"
                    shift 2
                else
                    echo "Error: --position requires a value" >&3
                    debug_function_exit "$function_name"
                    return 1
                fi
                ;;
            --help|-h)
                window_move_show_help
                debug_function_exit "$function_name"
                return 0
                ;;
            --positions)
                window_move_show_positions
                debug_function_exit "$function_name"
                return 0
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    # ──────────────────────────────────────────────
    # STEP 2: Extract window name and resolve mode arguments
    # ──────────────────────────────────────────────

    if [[ "$flag_mode" == true ]]; then
        # Flag mode: first positional arg = window name
        if [[ ${#positional_args[@]} -lt 1 ]]; then
            echo "Error: Window name required" >&3
            window_move_show_help
            debug_function_exit "$function_name"
            return 1
        fi
        window_name="${positional_args[0]}"

        # Must have at least one flag value
        if [[ -z "$new_desktop" && -z "$new_screen" && -z "$new_position" ]]; then
            echo "Error: At least one of --desktop, --screen, or --position required" >&3
            window_move_show_help
            debug_function_exit "$function_name"
            return 1
        fi
    else
        # Positional mode: name desktop [screen] [position]
        case ${#positional_args[@]} in
            0|1)
                echo "Error: Window name and at least one move target required" >&3
                window_move_show_help
                debug_function_exit "$function_name"
                return 1
                ;;
            2)
                window_name="${positional_args[0]}"
                new_desktop="${positional_args[1]}"
                ;;
            3)
                window_name="${positional_args[0]}"
                new_desktop="${positional_args[1]}"
                new_screen="${positional_args[2]}"
                ;;
            4)
                window_name="${positional_args[0]}"
                new_desktop="${positional_args[1]}"
                new_screen="${positional_args[2]}"
                new_position="${positional_args[3]}"
                ;;
            *)
                echo "Error: Too many arguments" >&3
                window_move_show_help
                debug_function_exit "$function_name"
                return 1
                ;;
        esac
    fi

    debug_log "$function_name" "Parsed: window='$window_name' desktop='$new_desktop' screen='$new_screen' position='$new_position' flag_mode=$flag_mode"

    # ──────────────────────────────────────────────
    # STEP 3: Validate window name and verify alive
    # ──────────────────────────────────────────────

    local uuid=""
    uuid=$(db_get_uuid "$window_name")
    if [[ -z "$uuid" ]]; then
        echo "Error: Window '$window_name' not found in tracked windows" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    if ! kdotool getwindowname "$uuid" &>/dev/null; then
        echo "Error: Window '$window_name' is no longer open" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # ──────────────────────────────────────────────
    # STEP 4: Validate provided values
    # ──────────────────────────────────────────────

    # Resolve position (abbreviation or full name → canonical value)
    if [[ -n "$new_position" ]]; then
        local resolved_position=""
        resolved_position=$(resolve_position "$new_position") || true
        if [[ -z "$resolved_position" ]]; then
            echo "Error: Invalid position '$new_position'" >&3
            window_move_show_positions
            debug_function_exit "$function_name"
            return 1
        fi
        new_position="$resolved_position"
        debug_log "$function_name" "Resolved position: '$new_position'"
    fi

    # Validate screen reference
    local target_screen_output=""
    if [[ -n "$new_screen" ]]; then
        target_screen_output=$(resolve_screen_reference "$new_screen") || true
        if [[ -z "$target_screen_output" ]]; then
            echo "Error: Invalid screen reference '$new_screen'" >&3
            debug_function_exit "$function_name"
            return 1
        fi
        debug_log "$function_name" "Resolved screen: '$new_screen' → output $target_screen_output"
    fi

    # Validate desktop number
    if [[ -n "$new_desktop" ]]; then
        validate_desktop_number "$new_desktop" || {
            echo "Error: Invalid desktop number '$new_desktop' (must be 1-$DETECTED_DESKTOP_COUNT)" >&3
            debug_function_exit "$function_name"
            return 1
        }
        debug_log "$function_name" "Validated desktop: $new_desktop"
    fi

    # ──────────────────────────────────────────────
    # STEP 5: Auto-detect current screen when needed
    # ──────────────────────────────────────────────

    local current_screen_output=""

    # Position without screen: need to know which screen the window is on
    if [[ -n "$new_position" && -z "$target_screen_output" ]]; then
        current_screen_output=$(detect_window_screen "$uuid") || true
        if [[ -z "$current_screen_output" ]]; then
            echo "Error: Could not detect which screen window '$window_name' is on" >&3
            debug_function_exit "$function_name"
            return 1
        fi
        target_screen_output="$current_screen_output"
        debug_log "$function_name" "Auto-detected current screen: output $current_screen_output"
    fi

    # ──────────────────────────────────────────────
    # STEP 6: Preserve position when moving to a new screen
    # ──────────────────────────────────────────────

    local use_relative_fallback=false
    local fallback_x=""
    local fallback_y=""
    local fallback_w=""
    local fallback_h=""

    if [[ -n "$target_screen_output" && -z "$new_position" ]]; then
        # Screen specified but position not — preserve current position
        if [[ -z "$current_screen_output" ]]; then
            current_screen_output=$(detect_window_screen "$uuid") || true
            if [[ -z "$current_screen_output" ]]; then
                echo "Error: Could not detect which screen window '$window_name' is on" >&3
                debug_function_exit "$function_name"
                return 1
            fi
        fi

        local detected_position=""
        detected_position=$(detect_window_position "$uuid" "$current_screen_output") || true

        if [[ -n "$detected_position" ]]; then
            new_position="$detected_position"
            debug_log "$function_name" "Preserving detected position: '$detected_position'"
        else
            # Fallback: preserve relative coordinates
            use_relative_fallback=true
            debug_log "$function_name" "Position unrecognized, using relative offset fallback"

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
            local old_sw=""
            local old_sh=""
            old_sx=$(get_screen_info "$current_screen_output" "X")
            old_sy=$(get_screen_info "$current_screen_output" "Y")
            old_sw=$(get_screen_info "$current_screen_output" "WIDTH")
            old_sh=$(get_screen_info "$current_screen_output" "HEIGHT")

            # Relative offset from old screen origin
            local rel_x=$((win_x - old_sx))
            local rel_y=$((win_y - old_sy))

            # Get new screen dimensions for clamping
            local new_sx=""
            local new_sy=""
            local new_sw=""
            local new_sh=""
            new_sx=$(get_screen_info "$target_screen_output" "X")
            new_sy=$(get_screen_info "$target_screen_output" "Y")
            new_sw=$(get_screen_info "$target_screen_output" "WIDTH")
            new_sh=$(get_screen_info "$target_screen_output" "HEIGHT")

            # Clamp to ensure window stays on-screen
            if (( rel_x + win_w > new_sw )); then
                rel_x=$((new_sw - win_w))
                if (( rel_x < 0 )); then
                    rel_x=0
                fi
            fi
            if (( rel_y + win_h > new_sh )); then
                rel_y=$((new_sh - win_h))
                if (( rel_y < 0 )); then
                    rel_y=0
                fi
            fi

            fallback_x=$((new_sx + rel_x))
            fallback_y=$((new_sy + rel_y))
            fallback_w="$win_w"
            fallback_h="$win_h"

            debug_log "$function_name" "Fallback target: ($fallback_x, $fallback_y) size: ${fallback_w}x${fallback_h}"
        fi
    fi

    # ──────────────────────────────────────────────
    # STEP 7: Execute moves
    # ──────────────────────────────────────────────

    # Desktop move (if specified)
    if [[ -n "$new_desktop" ]]; then
        move_window_to_desktop "$uuid" "$new_desktop"
        debug_log "$function_name" "Moved to desktop $new_desktop"
    fi

    # Screen + position move
    if [[ "$use_relative_fallback" == true ]]; then
        # Relative offset fallback — move and resize directly
        move_window "$uuid" "$fallback_x" "$fallback_y"
        size_window "$uuid" "$fallback_w" "$fallback_h"
        debug_log "$function_name" "Moved via relative fallback"
    elif [[ -n "$target_screen_output" && -n "$new_position" ]]; then
        # Known position on target screen
        move_window_to_screen "$uuid" "$target_screen_output"
        move_window_to_position "$uuid" "$target_screen_output" "$new_position"
        debug_log "$function_name" "Moved to screen $target_screen_output at '$new_position'"
    elif [[ -n "$new_position" ]]; then
        # Position only (target_screen_output was auto-detected in step 5)
        move_window_to_position "$uuid" "$target_screen_output" "$new_position"
        debug_log "$function_name" "Repositioned to '$new_position'"
    fi

    # ──────────────────────────────────────────────
    # STEP 8: Confirmation message
    # ──────────────────────────────────────────────

    local msg="Window '$window_name' moved:"
    if [[ -n "$new_desktop" ]]; then
        msg+=" desktop=$new_desktop"
    fi
    if [[ -n "$target_screen_output" ]]; then
        msg+=" screen=$target_screen_output"
    fi
    if [[ -n "$new_position" ]]; then
        msg+=" position='$new_position'"
    elif [[ "$use_relative_fallback" == true ]]; then
        msg+=" position=preserved"
    fi
    echo "$msg" >&3

    debug_function_exit "$function_name"
    return 0
}
