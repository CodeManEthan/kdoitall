#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_EXPORT_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/window-definitions.sh
source "${LIB_DIR}/db/window-definitions.sh"

workspace_export() {
    local workspace_name="${1:-}"
    local function_name="workspace_export"

    debug_function_enter "$function_name" "$@"

    # Validate workspace name provided
    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name is required." >&2
        echo "Usage: kdoitall workspace export <name>" >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    # Check workspace exists
    if ! db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' not found." >&2
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_NOT_FOUND"
    fi

    # Get workspace metadata (pipe-delimited: workspace_name|description|created_at|is_active|last_opened_at)
    local workspace_data=""
    workspace_data=$(db_get_workspace "$workspace_name")
    local ws_description=""
    ws_description=$(echo "$workspace_data" | cut -d'|' -f2)

    # Get focus window
    local focus_window=""
    focus_window=$(db_get_workspace_focus_window "$workspace_name")

    # Get window definitions (pipe-delimited: window_name|workspace_name|app_id|launch_function|desktop|screen|position|parameters|display_order)
    local window_data=""
    window_data=$(db_list_window_definitions "$workspace_name")

    if [[ -z "$window_data" ]]; then
        echo "Error: Workspace '$workspace_name' has no window definitions." >&2
        debug_function_exit "$function_name"
        return "$ERR_WINDOW_DEFINITION_NOT_FOUND"
    fi

    # Build windows JSON array
    local windows_json="[]"
    while IFS='|' read -r win_name _ win_app win_function win_desktop win_screen win_position win_params _; do
        # Resolve position variable name to display value
        local position_display=""
        position_display="${!win_position:-$win_position}"

        # Build window object — omit function when it's the default, omit params when empty
        local win_obj=""
        if [[ "$win_function" == "launch_by_app_id" && -z "$win_params" ]]; then
            win_obj=$(jq -n \
                --arg name "$win_name" \
                --arg app "$win_app" \
                --argjson desktop "$win_desktop" \
                --arg screen "$win_screen" \
                --arg position "$position_display" \
                '{name: $name, app: $app, desktop: $desktop, screen: $screen, position: $position}')
        elif [[ "$win_function" == "launch_by_app_id" ]]; then
            win_obj=$(jq -n \
                --arg name "$win_name" \
                --arg app "$win_app" \
                --argjson desktop "$win_desktop" \
                --arg screen "$win_screen" \
                --arg position "$position_display" \
                --arg params "$win_params" \
                '{name: $name, app: $app, desktop: $desktop, screen: $screen, position: $position, params: $params}')
        elif [[ -z "$win_params" ]]; then
            win_obj=$(jq -n \
                --arg name "$win_name" \
                --arg app "$win_app" \
                --arg function "$win_function" \
                --argjson desktop "$win_desktop" \
                --arg screen "$win_screen" \
                --arg position "$position_display" \
                '{name: $name, app: $app, function: $function, desktop: $desktop, screen: $screen, position: $position}')
        else
            win_obj=$(jq -n \
                --arg name "$win_name" \
                --arg app "$win_app" \
                --arg function "$win_function" \
                --argjson desktop "$win_desktop" \
                --arg screen "$win_screen" \
                --arg position "$position_display" \
                --arg params "$win_params" \
                '{name: $name, app: $app, function: $function, desktop: $desktop, screen: $screen, position: $position, params: $params}')
        fi

        windows_json=$(echo "$windows_json" | jq --argjson win "$win_obj" '. + [$win]')
    done <<< "$window_data"

    # Assemble final JSON object — omit optional fields when empty
    local final_args=()
    final_args+=(--arg workspace "$workspace_name")
    final_args+=(--argjson windows "$windows_json")

    local jq_expr='{workspace: $workspace'

    if [[ -n "$ws_description" ]]; then
        final_args+=(--arg description "$ws_description")
        jq_expr+=', description: $description'
    fi

    if [[ -n "$focus_window" ]]; then
        final_args+=(--arg focus_window "$focus_window")
        jq_expr+=', focus_window: $focus_window'
    fi

    jq_expr+=', windows: $windows}'

    # Output to stdout (not fd 3) so it can be piped/redirected
    jq -n "${final_args[@]}" "$jq_expr"

    debug_function_exit "$function_name"
    return 0
}
