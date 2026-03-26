#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_IMPORT_LOADED" || return 0

# shellcheck source=../../workspace/generator.sh
source "${LIB_DIR}/workspace/generator.sh"
# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../../db/window-definitions.sh
source "${LIB_DIR}/db/window-definitions.sh"
# shellcheck source=../../utils/workspace-validators.sh
source "${LIB_DIR}/utils/workspace-validators.sh"

workspace_create_from_file() {
    local workspace_name="$1"
    local file_path="$2"
    local replace_flag="$3"
    local description=""
    local focus_window_name=""
    local function_name="workspace_create_from_file"

    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()

    debug_function_enter "$function_name" "$@"

    # Validate workspace name
    if ! validate_workspace_name "$workspace_name"; then
        debug_function_exit "$function_name"
        return "$ERR_INVALID_WORKSPACE_NAME"
    fi

    # Validate file path provided
    if [[ -z "$file_path" ]]; then
        echo "Error: Config file path is required." >&2
        echo "Usage: kdoitall workspace create <name> --from-file <path>" >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    # Validate file exists
    if [[ ! -f "$file_path" ]]; then
        echo "Error: Config file not found: $file_path" >&2
        debug_function_exit "$function_name"
        return "$ERR_FILE_NOT_FOUND"
    fi

    # Validate JSON syntax
    if ! jq empty "$file_path" 2>/dev/null; then
        echo "Error: Invalid JSON in config file: $file_path" >&2
        debug_function_exit "$function_name"
        return "$ERR_INVALID_CONFIG_FILE"
    fi

    # Parse and validate config — populates WORKSPACE_APPS, description, focus_window_name
    echo "Validating config file..." >&3
    if ! parse_and_validate_workspace_config "$file_path" "$workspace_name" "$replace_flag"; then
        debug_function_exit "$function_name"
        return "$ERR_IMPORT_VALIDATION_FAILED"
    fi

    # Handle workspace existence
    if db_workspace_exists "$workspace_name"; then
        if [[ "$replace_flag" == "true" ]]; then
            # Prevent replacing an active workspace
            local is_active=""
            is_active=$(db_get_workspace_is_active "$workspace_name")
            if [[ "$is_active" == "1" ]]; then
                echo "Error: Cannot replace workspace '$workspace_name' while it is active." >&2
                echo "Close the workspace first with: kdoitall workspace close $workspace_name" >&3
                debug_function_exit "$function_name"
                return "$ERR_WORKSPACE_IS_ACTIVE"
            fi
            echo "Replacing existing workspace: $workspace_name" >&3
            if ! db_delete_workspace "$workspace_name"; then
                echo "Error: Failed to delete existing workspace: $workspace_name" >&2
                debug_function_exit "$function_name"
                return "$ERR_DATABASE_ERROR"
            fi
        else
            echo "Error: Workspace '$workspace_name' already exists." >&2
            echo "Use --replace to replace an existing workspace." >&3
            debug_function_exit "$function_name"
            return "$ERR_WORKSPACE_EXISTS"
        fi
    fi

    # Create workspace in database
    if ! db_create_workspace "$workspace_name" "$description"; then
        echo "Error: Failed to create workspace in database." >&2
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_INSERT_FAILED"
    fi

    # Set focus window if configured
    if [[ -n "$focus_window_name" ]]; then
        if ! db_set_workspace_focus_window "$workspace_name" "$focus_window_name"; then
            echo "Warning: Failed to set focus window preference." >&3
        fi
    fi

    # Generate workspace scripts (also stores window definitions via store_window_definitions)
    if ! generate_workspace_scripts "$workspace_name"; then
        echo "Error: Script generation failed. Rolling back workspace..." >&2
        db_delete_workspace "$workspace_name"
        debug_function_exit "$function_name"
        return "$ERR_SCRIPT_GENERATION_FAILED"
    fi

    echo "" >&3
    echo "Workspace '$workspace_name' created successfully from $file_path" >&3
    echo "" >&3
    echo "Open with:  kdoitall workspace open $workspace_name" >&3
    echo "Close with: kdoitall workspace close $workspace_name" >&3

    debug_function_exit "$function_name"
    return 0
}

parse_and_validate_workspace_config() {
    local file_path="$1"
    local workspace_name="$2"
    local replace_flag="$3"
    local function_name="parse_and_validate_workspace_config"
    local error_count=0

    debug_function_enter "$function_name" "$@"

    # Extract top-level fields
    local json_workspace=""
    json_workspace=$(jq -r '.workspace // empty' "$file_path")

    # Warn if workspace field doesn't match CLI argument
    if [[ -n "$json_workspace" && "$json_workspace" != "$workspace_name" ]]; then
        echo "Warning: Config file workspace name '$json_workspace' differs from CLI argument '$workspace_name'. Using '$workspace_name'." >&3
    fi

    # Extract description
    description=$(jq -r '.description // empty' "$file_path")

    # Extract focus_window
    local json_focus_window=""
    json_focus_window=$(jq -r '.focus_window // empty' "$file_path")

    # Verify windows array exists and is non-empty
    local window_count=0
    window_count=$(jq '.windows | length' "$file_path" 2>/dev/null)

    if [[ -z "$window_count" || "$window_count" -eq 0 ]]; then
        echo "Error: Config file must contain a non-empty 'windows' array." >&2
        ((error_count++)) || true
        debug_function_exit "$function_name"
        return 1
    fi

    # Track window names for uniqueness within the file
    local -a seen_names=()
    local window_index=0

    # Iterate over windows
    local window_json=""
    while IFS= read -r window_json; do
        local win_name=""
        local win_app=""
        local win_function=""
        local win_desktop=""
        local win_screen=""
        local win_position=""
        local win_params=""
        local window_errors=0

        win_name=$(echo "$window_json" | jq -r '.name // empty')
        win_app=$(echo "$window_json" | jq -r '.app // empty')
        win_function=$(echo "$window_json" | jq -r '.function // empty')
        win_desktop=$(echo "$window_json" | jq -r '.desktop // empty')
        win_screen=$(echo "$window_json" | jq -r '.screen // empty')
        win_position=$(echo "$window_json" | jq -r '.position // empty')
        win_params=$(echo "$window_json" | jq -r '.params // empty')

        local window_label="Window $((window_index + 1))/$window_count"

        # Validate name
        if [[ -z "$win_name" ]]; then
            echo "Error: $window_label: 'name' is required." >&2
            ((window_errors++)) || true
        else
            if ! validate_window_name "$win_name" 2>/dev/null 3>/dev/null; then
                echo "Error: Window '$win_name': invalid window name format." >&2
                ((window_errors++)) || true
            fi

            # Check uniqueness within file
            local seen=""
            for seen in "${seen_names[@]}"; do
                if [[ "$seen" == "$win_name" ]]; then
                    echo "Error: Window '$win_name': duplicate window name in config file." >&2
                    ((window_errors++)) || true
                    break
                fi
            done

            # Check global uniqueness (skip if --replace and window belongs to same workspace)
            if db_window_definition_exists "$win_name"; then
                if [[ "$replace_flag" == "true" ]]; then
                    # Check if this window belongs to the workspace being replaced
                    local existing_def=""
                    existing_def=$(db_get_window_definition "$win_name" 2>/dev/null)
                    local existing_workspace=""
                    existing_workspace=$(echo "$existing_def" | cut -d'|' -f2)
                    if [[ "$existing_workspace" != "$workspace_name" ]]; then
                        echo "Error: Window '$win_name': name already in use by workspace '$existing_workspace'." >&2
                        ((window_errors++)) || true
                    fi
                else
                    echo "Error: Window '$win_name': name already in use by another workspace." >&2
                    ((window_errors++)) || true
                fi
            fi

            seen_names+=("$win_name")
        fi

        # Validate app
        if [[ -z "$win_app" ]]; then
            echo "Error: ${window_label}${win_name:+ ($win_name)}: 'app' is required." >&2
            ((window_errors++)) || true
        elif ! db_application_exists "$win_app"; then
            echo "Error: Window '$win_name': app '$win_app' not found. Run 'kdoitall app scan' first." >&2
            ((window_errors++)) || true
        fi

        # Validate function
        local resolved_function="launch_by_app_id"
        if [[ -n "$win_function" && "$win_function" != "launch_by_app_id" ]]; then
            resolved_function="$win_function"
            # Verify function exists in launch_options for this app
            if [[ -n "$win_app" ]] && db_application_exists "$win_app" 2>/dev/null; then
                local launch_opts=""
                launch_opts=$(db_get_launch_options "$win_app")
                if [[ -z "$launch_opts" ]] || ! echo "$launch_opts" | grep -q "^${win_function}|"; then
                    echo "Error: Window '$win_name': function '$win_function' not found for app '$win_app'." >&2
                    ((window_errors++)) || true
                fi
            fi
        fi

        # Validate desktop
        if [[ -z "$win_desktop" ]]; then
            echo "Error: Window '$win_name': 'desktop' is required." >&2
            ((window_errors++)) || true
        elif ! [[ "$win_desktop" =~ ^[0-9]+$ ]] || [[ "$win_desktop" -lt 1 ]] || [[ "$win_desktop" -gt "$DETECTED_DESKTOP_COUNT" ]]; then
            echo "Error: Window '$win_name': desktop '$win_desktop' is not valid (must be 1-$DETECTED_DESKTOP_COUNT)." >&2
            ((window_errors++)) || true
        fi

        # Validate screen
        local resolved_screen=""
        if [[ -z "$win_screen" ]]; then
            echo "Error: Window '$win_name': 'screen' is required." >&2
            ((window_errors++)) || true
        elif ! resolved_screen=$(resolve_screen_reference "$win_screen" 2>/dev/null); then
            echo "Error: Window '$win_name': screen '$win_screen' is not valid." >&2
            ((window_errors++)) || true
        fi

        # Validate position
        local resolved_position=""
        if [[ -z "$win_position" ]]; then
            echo "Error: Window '$win_name': 'position' is required." >&2
            ((window_errors++)) || true
        elif ! resolved_position=$(resolve_position_reference "$win_position" 2>/dev/null); then
            echo "Error: Window '$win_name': position '$win_position' is not valid. Use a position name (FULLSCREEN), abbreviation (fs), or display name (Fullscreen)." >&2
            ((window_errors++)) || true
        fi

        # Report per-window status
        if [[ "$window_errors" -gt 0 ]]; then
            echo "  $window_label: ${win_name:-<unnamed>} (${win_app:-<no app>}) — ERROR" >&3
            error_count=$((error_count + window_errors))
        else
            echo "  $window_label: $win_name ($win_app) — OK" >&3

            # Build WORKSPACE_APPS entry
            WORKSPACE_APPS+=("${win_app}|${win_name}|${resolved_function}|${win_desktop}|${resolved_screen}|${resolved_position}|${win_params}")
        fi

        ((window_index++)) || true
    done < <(jq -c '.windows[]' "$file_path")

    # Validate focus_window matches a window name
    if [[ -n "$json_focus_window" ]]; then
        local found_focus=false
        local check_name=""
        for check_name in "${seen_names[@]}"; do
            if [[ "$check_name" == "$json_focus_window" ]]; then
                found_focus=true
                break
            fi
        done

        if [[ "$found_focus" == "true" ]]; then
            focus_window_name="$json_focus_window"
        else
            echo "Error: focus_window '$json_focus_window' does not match any window name in the config." >&2
            ((error_count++)) || true
        fi
    fi

    if [[ "$error_count" -gt 0 ]]; then
        echo "" >&3
        echo "Validation failed with $error_count error(s)." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "Config validation passed: ${#WORKSPACE_APPS[@]} windows"
    debug_function_exit "$function_name"
    return 0
}
