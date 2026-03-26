#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_NAME_COMMAND_LOADED" || return 0

# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"

app_name_command() {
    local function_name="app_name_command"
    local first_arg="${1:-}"
    local second_arg="${2:-}"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$first_arg" ]]; then
        echo "Usage: kdoitall app name <app_id> <new_name>" >&2
        echo "       kdoitall app name reset <app_id>" >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Handle reset subcommand
    if [[ "$first_arg" == "reset" ]]; then
        if [[ -z "$second_arg" ]]; then
            print_error "Usage: kdoitall app name reset <app_id>"
            debug_function_exit "$function_name"
            return 1
        fi
        _app_name_reset "$second_arg"
        debug_function_exit "$function_name"
        return $?
    fi

    # Set mode: app name <app_id> <new_name>
    local app_id="$first_arg"
    local new_name="$second_arg"

    if [[ -z "$new_name" ]]; then
        print_error "Usage: kdoitall app name <app_id> <new_name>"
        debug_function_exit "$function_name"
        return 1
    fi

    _app_name_set "$app_id" "$new_name"
    debug_function_exit "$function_name"
    return $?
}

_app_name_set() {
    local app_id="$1"
    local new_name="$2"
    local function_name="_app_name_set"

    debug_function_enter "$function_name" "$@"

    # Verify application exists
    if ! db_application_exists "$app_id"; then
        print_error "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate name format: lowercase, alphanumeric + hyphens only
    if [[ ! "$new_name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        print_error "Invalid name format: '$new_name'"
        echo "  Names must be lowercase, alphanumeric + hyphens, and cannot start or end with a hyphen." >&3
        debug_function_exit "$function_name"
        return "$ERR_INVALID_VALUE"
    fi

    # Check for conflicts with existing app names
    if db_check_app_name_exists "$new_name" "$app_id"; then
        print_error "Name '$new_name' is already in use by another application"
        debug_function_exit "$function_name"
        return "$ERR_APP_NAME_CONFLICT"
    fi

    # Set the name and mark as manual
    if ! db_set_app_name "$app_id" "$new_name" 1; then
        print_error "Failed to set app name"
        debug_function_exit "$function_name"
        return "$ERR_DATABASE_ERROR"
    fi

    # Update existing app_windows rows
    db_update_app_windows_app_name "$app_id" "$new_name"

    local display_name=""
    display_name=$(db_get_display_name "$app_id")
    print_success "Set app name: $app_id ($display_name) -> '$new_name'"

    debug_function_exit "$function_name"
    return 0
}

_app_name_reset() {
    local app_id="$1"
    local function_name="_app_name_reset"

    debug_function_enter "$function_name" "$@"

    # Verify application exists
    if ! db_application_exists "$app_id"; then
        print_error "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    # Clear the manual flag (name will be auto-generated on next scan)
    db_query \
        "UPDATE applications SET app_name_manual = 0 WHERE app_id = :app_id;" \
        ":app_id" "$app_id"

    if [[ "$DB_STATUS" != "OK" ]]; then
        print_error "Failed to reset app name"
        debug_function_exit "$function_name"
        return "$ERR_DATABASE_ERROR"
    fi

    local display_name=""
    display_name=$(db_get_display_name "$app_id")
    print_success "Reset app name for: $app_id ($display_name)"
    echo "  Run 'kdoitall app scan' to auto-generate a new name." >&3

    debug_function_exit "$function_name"
    return 0
}
