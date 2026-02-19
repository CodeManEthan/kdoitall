#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_UPDATE_COMMAND_LOADED" || return 0

# shellcheck source=../db/app-registry.sh
source "${LIB_DIR}/db/app-registry.sh"

update_command() {
    local function_name="update_command"
    local old_version=""
    local new_version=""
    local old_app_count=""
    local new_app_count=""
    local registry_seed=""
    local registry_db=""

    debug_function_enter "$function_name"

    old_version=$(cat "${KDOITALL_ROOT}/VERSION")
    registry_seed="${KDOITALL_ROOT}/database/app-registry.sql"
    registry_db="$KDOITALL_REGISTRY_DB"

    # Get old app count before update
    old_app_count=$(app_registry_count_apps)

    echo "Updating kdoitall..." >&3

    # --- Git pull ---
    if ! git -C "$KDOITALL_ROOT" pull --ff-only 2>&1; then
        echo "" >&3
        echo "✗ Git pull failed. Resolve any conflicts and try again." >&2
        debug_error "$function_name" "$ERR_UNKNOWN" "git pull --ff-only failed"
        debug_function_exit "$function_name"
        return 1
    fi

    new_version=$(cat "${KDOITALL_ROOT}/VERSION")

    # --- Rebuild reference database ---
    if [[ -f "$registry_seed" ]]; then
        rm -f "$registry_db"
        sqlite3 "$registry_db" < "$registry_seed"

        new_app_count=$(app_registry_count_apps)

        local app_diff=""
        app_diff=$((new_app_count - old_app_count))

        local app_diff_display=""
        if [[ "$app_diff" -gt 0 ]]; then
            app_diff_display=", +${app_diff} new"
        elif [[ "$app_diff" -lt 0 ]]; then
            app_diff_display=", ${app_diff} removed"
        fi

        echo "✓ Rebuilt app registry (${new_app_count} apps${app_diff_display})" >&3
    else
        echo "⚠ App registry seed file not found — skipping rebuild" >&3
    fi

    # --- Report version change ---
    if [[ "$old_version" != "$new_version" ]]; then
        echo "✓ Updated to v${new_version} (was v${old_version})" >&3
    else
        echo "✓ Already at v${new_version}" >&3
    fi

    echo "✓ Done" >&3

    debug_function_exit "$function_name"
    return 0
}
