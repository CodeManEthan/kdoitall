#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SCREEN_ALIAS_LOADED" || return 0

# shellcheck source=../../db/screen.sh
source "${LIB_DIR}/db/screen.sh"

screen_alias() {
    local function_name="screen_alias"

    debug_function_enter "$function_name" "$@"

    # Handle "remove" subcommand
    if [[ "${1:-}" == "remove" ]]; then
        local alias_name="${2:-}"

        if [[ -z "$alias_name" ]]; then
            echo "Error: Alias name required" >&2
            echo "Usage: kdoitall screen alias remove <alias>" >&2
            debug_function_exit "$function_name"
            return 1
        fi

        if db_remove_screen_alias "$alias_name"; then
            echo "✓ Alias '$alias_name' removed" >&3
        else
            echo "Error: Alias '$alias_name' not found" >&3
        fi

        debug_function_exit "$function_name"
        return 0
    fi

    # Handle "set" (positional: alias target)
    local alias_name="${1:-}"
    local target="${2:-}"

    if [[ -z "$alias_name" || -z "$target" ]]; then
        echo "Error: Alias name and target required" >&2
        echo "Usage: kdoitall screen alias <alias> <target>" >&2
        echo "       kdoitall screen alias remove <alias>" >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate alias name: not empty, alphanumeric/hyphens/underscores, not a pure number, max 50 chars
    if [[ ${#alias_name} -gt 50 ]]; then
        echo "Error: Alias name too long (max 50 characters)" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    if ! [[ "$alias_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid characters in alias name (use alphanumeric, hyphens, underscores)" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ "$alias_name" =~ ^[0-9]+$ ]]; then
        echo "Error: Alias name cannot be a pure number (would conflict with screen numbers)" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Resolve the target to verify it points to a valid screen
    local resolved_output=""
    if ! resolved_output=$(resolve_screen_reference "$target"); then
        echo "Error: Target '$target' does not resolve to an enabled screen" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Store the persistent screen name, not the volatile output number
    local screen_name=""
    screen_name=$(get_screen_info "$resolved_output" "NAME")

    if ! db_set_screen_alias "$alias_name" "$screen_name"; then
        debug_function_exit "$function_name"
        return 1
    fi

    echo "✓ Alias '$alias_name' set to '$screen_name'" >&3
    debug_function_exit "$function_name"
    return 0
}
