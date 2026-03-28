#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_SET_TERMINAL_LOADED" || return 0

# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/terminal-emulator.sh
source "${LIB_DIR}/db/terminal-emulator.sh"
# shellcheck source=../../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../../app/registry.sh
source "${LIB_DIR}/app/registry.sh"
# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"

app_set_terminal() {
    local app_id="${1:-}"
    local exec_flag="${2:--e}"
    local function_name="app_set_terminal"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$app_id" ]]; then
        echo "Usage: kdoitall app set-terminal <app_id> [exec_flag]" >&3
        echo "" >&3
        echo "Marks an application as a terminal emulator and registers" >&3
        echo "shared terminal launch options for it." >&3
        echo "" >&3
        echo "Common exec flags:" >&3
        echo "  -e          konsole, alacritty, xfce4-terminal (default)" >&3
        echo "  --          gnome-terminal" >&3
        echo "  start --    wezterm" >&3
        echo "  (empty)     kitty (pass empty string \"\")" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate app exists
    if ! db_application_exists "$app_id"; then
        echo "Error: Application not found: $app_id" >&3
        echo "  Run 'kdoitall app scan' first to discover installed applications." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Register as terminal emulator
    if ! db_upsert_terminal_emulator "$app_id" "$exec_flag" "manual"; then
        echo "Error: Failed to register terminal emulator: $app_id" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Register shared terminal launch options
    registry_store_shared_terminal_launch_options "$app_id"

    local display_name=""
    display_name=$(db_get_display_name "$app_id") || display_name="$app_id"

    print_success "Marked '$display_name' ($app_id) as terminal emulator (exec flag: '${exec_flag}')"

    debug_function_exit "$function_name"
    return 0
}

app_unset_terminal() {
    local app_id="${1:-}"
    local function_name="app_unset_terminal"

    debug_function_enter "$function_name" "$@"

    if [[ -z "$app_id" ]]; then
        echo "Usage: kdoitall app unset-terminal <app_id>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Validate app exists
    if ! db_application_exists "$app_id"; then
        echo "Error: Application not found: $app_id" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    if ! db_is_terminal_emulator "$app_id"; then
        echo "Application is not classified as a terminal emulator: $app_id" >&3
        debug_function_exit "$function_name"
        return 0
    fi

    # Remove terminal emulator classification
    db_delete_terminal_emulator "$app_id"

    # Remove shared terminal launch options (terminal_* functions)
    # Keep any per-app launch options that might exist
    db_query \
        "DELETE FROM launch_parameters WHERE function_id IN (
            SELECT id FROM launch_options WHERE app_id = :app_id AND function_name LIKE 'terminal_%'
        );" \
        ":app_id" "$app_id"

    db_query \
        "DELETE FROM launch_options WHERE app_id = :app_id AND function_name LIKE 'terminal_%';" \
        ":app_id" "$app_id"

    # If no launch options remain, clear has_terminal_launch
    if ! db_app_has_launch_options "$app_id"; then
        db_query \
            "UPDATE applications SET has_terminal_launch = FALSE WHERE app_id = :app_id;" \
            ":app_id" "$app_id"
    fi

    local display_name=""
    display_name=$(db_get_display_name "$app_id") || display_name="$app_id"

    print_success "Removed terminal emulator classification for '$display_name' ($app_id)"

    debug_function_exit "$function_name"
    return 0
}
