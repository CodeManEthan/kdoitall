#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SCREEN_ALIAS_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
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
            print_success "Alias '$alias_name' removed"
        else
            print_error "Alias '$alias_name' not found"
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
        print_error "Alias name too long (max 50 characters)"
        debug_function_exit "$function_name"
        return 1
    fi

    if ! [[ "$alias_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid characters in alias name (use alphanumeric, hyphens, underscores)"
        debug_function_exit "$function_name"
        return 1
    fi

    if [[ "$alias_name" =~ ^[0-9]+$ ]]; then
        print_error "Alias name cannot be a pure number (would conflict with screen numbers)"
        debug_function_exit "$function_name"
        return 1
    fi

    # Resolve the target to verify it points to a valid screen
    local resolved_output=""
    if ! resolved_output=$(resolve_screen_reference "$target"); then
        print_error "Target '$target' does not resolve to an enabled screen"
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

    print_success "Alias '$alias_name' set to '$screen_name'"
    debug_function_exit "$function_name"
    return 0
}
