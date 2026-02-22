#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_EDIT_LOADED" || return 0

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
# shellcheck source=create.sh
source "${LIB_DIR}/commands/workspace/create.sh"

workspace_edit() {
    local workspace_name="$1"
    local function_name="workspace_edit"
    local description=""
    local has_changes=false

    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()

    debug_function_enter "$function_name" "$@"

    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name required" >&2
        echo "Usage: kdoitall workspace edit <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Check if workspace exists
    if ! db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' not found" >&2
        debug_function_exit "$function_name"
        return 1
    fi

    # Load current workspace metadata
    local workspace_data=""
    workspace_data=$(db_get_workspace "$workspace_name")
    IFS='|' read -r _ description _ _ _ <<< "$workspace_data"

    # Load current window definitions into WORKSPACE_APPS array
    if ! _edit_load_window_definitions "$workspace_name" WORKSPACE_APPS; then
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    echo "Editing workspace: $workspace_name" >&3

    # Main edit loop
    while true; do
        echo "" >&3
        _edit_show_summary "$workspace_name" "$description" WORKSPACE_APPS
        echo "" >&3
        _edit_show_menu

        local choice=""
        read -r choice

        case "$choice" in
            1)
                local new_description=""
                echo "" >&3
                echo "Current description: ${description:-<none>}" >&3
                echo "Enter new description (press Enter to keep current):" >&3
                read -r new_description

                if [[ -n "$new_description" ]]; then
                    description="$new_description"
                    has_changes=true
                    echo "✓ Description updated" >&3
                fi
                ;;
            2)
                local display_order=${#WORKSPACE_APPS[@]}
                ((display_order++))

                echo "" >&3
                echo "=== Add Application to Workspace ===" >&3
                echo "" >&3

                if add_application_to_workspace "$workspace_name" "$display_order" WORKSPACE_APPS; then
                    has_changes=true
                else
                    echo "Application addition cancelled." >&3
                fi
                ;;
            3)
                if _edit_window "$workspace_name" WORKSPACE_APPS; then
                    has_changes=true
                fi
                ;;
            4)
                if _edit_remove_window WORKSPACE_APPS; then
                    has_changes=true
                fi
                ;;
            5)
                if [[ "$has_changes" != true ]]; then
                    echo "" >&3
                    echo "No changes to save." >&3
                    continue
                fi

                if _edit_save "$workspace_name" "$description" WORKSPACE_APPS; then
                    debug_function_exit "$function_name"
                    return 0
                fi
                ;;
            6)
                if [[ "$has_changes" == true ]]; then
                    echo "" >&3
                    echo "You have unsaved changes. Discard and exit? (y/n)" >&3
                    local confirm_cancel=""
                    read -r confirm_cancel

                    if [[ "$confirm_cancel" != "y" ]]; then
                        continue
                    fi
                fi

                echo "Edit cancelled." >&3
                debug_function_exit "$function_name"
                return 0
                ;;
            *)
                echo "Invalid choice. Please select 1-6." >&3
                ;;
        esac
    done
}

_edit_load_window_definitions() {
    local workspace_name="$1"
    # apps_array_ref="$2"
    local function_name="_edit_load_window_definitions"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$2" "apps_array_ref" || return 1
    local -n apps_array_ref="$2"

    local window_defs=""
    window_defs=$(db_list_window_definitions "$workspace_name")

    if [[ -z "$window_defs" ]]; then
        debug_log "$function_name" "No window definitions found for workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    fi

    while IFS='|' read -r window_name _ app_id launch_function desktop screen position parameters _; do
        [[ -z "$window_name" ]] && continue
        apps_array_ref+=("${app_id}|${window_name}|${launch_function}|${desktop}|${screen}|${position}|${parameters}")
    done <<< "$window_defs"

    debug_log "$function_name" "Loaded ${#apps_array_ref[@]} window definitions"
    debug_function_exit "$function_name"
    return 0
}

_edit_show_summary() {
    local workspace_name="$1"
    local description="$2"
    # apps_ref="$3"
    local -n apps_ref="$3"

    echo "=== Current Configuration ===" >&3
    echo "Workspace: $workspace_name" >&3
    echo "Description: ${description:-<none>}" >&3
    echo "" >&3

    if [[ ${#apps_ref[@]} -eq 0 ]]; then
        echo "Windows: (none)" >&3
        return 0
    fi

    echo "Windows (${#apps_ref[@]}):" >&3

    local idx=0
    local app_entry=""
    for app_entry in "${apps_ref[@]}"; do
        local s_app_id=""
        local s_window_name=""
        local s_desktop=""
        local s_screen=""
        local s_position=""
        local s_name=""
        IFS='|' read -r s_app_id s_window_name _ s_desktop s_screen s_position _ <<< "$app_entry"

        s_name=""
        s_name=$(db_get_display_name "$s_app_id") || s_name="$s_app_id"

        idx=$((idx + 1))
        printf "  %d. %-22s %-30s Screen %s, Desktop %s, %s\n" \
            "$idx" "$s_name" "($s_window_name)" "$s_screen" "$s_desktop" "$s_position" >&3
    done
}

_edit_show_menu() {
    echo "Edit Options:" >&3
    echo "  1) Edit description" >&3
    echo "  2) Add window" >&3
    echo "  3) Edit window" >&3
    echo "  4) Remove window" >&3
    echo "  5) Save and apply changes" >&3
    echo "  6) Cancel" >&3
    echo "" >&3
    echo "Select option (1-6):" >&3
}

_edit_remove_window() {
    # apps_array_ref="$1"
    local -n apps_array_ref="$1"
    local function_name="_edit_remove_window"

    debug_function_enter "$function_name"

    if [[ ${#apps_array_ref[@]} -eq 0 ]]; then
        echo "No windows to remove." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    echo "Select window to remove (1-${#apps_array_ref[@]}, or 'c' to cancel):" >&3
    local selection=""
    read -r selection

    if [[ "$selection" == "c" ]]; then
        debug_function_exit "$function_name"
        return 1
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [[ "$selection" -lt 1 ]] || \
       [[ "$selection" -gt ${#apps_array_ref[@]} ]]; then
        echo "Invalid selection." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    local idx=$((selection - 1))
    local removed_entry="${apps_array_ref[$idx]}"
    local removed_name=""
    removed_name=$(echo "$removed_entry" | cut -d'|' -f2)

    # Remove element from array
    unset 'apps_array_ref[idx]'
    # Re-index to close the gap
    apps_array_ref=("${apps_array_ref[@]}")

    echo "✓ Removed window: $removed_name" >&3

    debug_function_exit "$function_name"
    return 0
}

_edit_window() {
    local workspace_name="$1"
    # apps_array_ref="$2"
    local -n apps_array_ref="$2"
    local function_name="_edit_window"

    debug_function_enter "$function_name"

    if [[ ${#apps_array_ref[@]} -eq 0 ]]; then
        echo "No windows to edit." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    echo "Select window to edit (1-${#apps_array_ref[@]}, or 'c' to cancel):" >&3
    local selection=""
    read -r selection

    if [[ "$selection" == "c" ]]; then
        debug_function_exit "$function_name"
        return 1
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [[ "$selection" -lt 1 ]] || \
       [[ "$selection" -gt ${#apps_array_ref[@]} ]]; then
        echo "Invalid selection." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    local idx=$((selection - 1))
    local entry="${apps_array_ref[$idx]}"
    local e_app_id=""
    local e_window_name=""
    local e_launch_function=""
    local e_desktop=""
    local e_screen=""
    local e_position=""
    local e_parameters=""
    IFS='|' read -r e_app_id e_window_name e_launch_function e_desktop e_screen e_position e_parameters <<< "$entry"

    local e_display_name=""
    e_display_name=$(db_get_display_name "$e_app_id") || e_display_name="$e_app_id"

    local modified=false

    echo "" >&3
    echo "Editing window: $e_window_name ($e_display_name)" >&3
    echo "  Desktop:         $e_desktop" >&3
    echo "  Screen:          $e_screen" >&3
    echo "  Position:        $e_position" >&3
    echo "  Launch function: $e_launch_function" >&3
    echo "  Parameters:      ${e_parameters:-<none>}" >&3
    echo "" >&3
    echo "What would you like to change?" >&3
    echo "  1) Desktop" >&3
    echo "  2) Screen" >&3
    echo "  3) Position" >&3
    echo "  4) Launch function" >&3
    echo "  5) Parameters" >&3
    echo "  6) Cancel" >&3
    echo "" >&3
    echo "Select option (1-6):" >&3

    local edit_choice=""
    read -r edit_choice

    case "$edit_choice" in
        1)
            local new_desktop=""
            if new_desktop=$(select_desktop_with_retry); then
                e_desktop="$new_desktop"
                modified=true
                echo "✓ Desktop updated to: $e_desktop" >&3
            fi
            ;;
        2)
            local new_screen=""
            if new_screen=$(select_screen_with_retry); then
                e_screen="$new_screen"
                modified=true
                echo "✓ Screen updated to: $e_screen" >&3
            fi
            ;;
        3)
            local new_position=""
            if new_position=$(select_position_with_retry); then
                e_position="$new_position"
                modified=true
                echo "✓ Position updated to: $e_position" >&3
            fi
            ;;
        4)
            if [[ "$e_launch_function" == "launch_by_app_id" ]]; then
                echo "" >&3
                echo "This window uses desktop launch (launch_by_app_id)." >&3
                echo "To change launch function, the app must support terminal launch." >&3

                local app_info_ef=""
                app_info_ef=$(db_get_application "$e_app_id")
                local has_terminal_ef=""
                has_terminal_ef=$(echo "$app_info_ef" | cut -d'|' -f7)

                if [[ "$has_terminal_ef" != "1" && "$has_terminal_ef" != "TRUE" ]]; then
                    echo "This application does not support terminal launch." >&3
                else
                    echo "Switch to terminal launch? (y/n)" >&3
                    local switch_confirm=""
                    read -r switch_confirm

                    if [[ "$switch_confirm" == "y" ]]; then
                        local new_func=""
                        if new_func=$(select_launch_function_with_retry "$e_app_id"); then
                            e_launch_function="$new_func"
                            modified=true
                            echo "✓ Launch function updated to: $e_launch_function" >&3
                        fi
                    fi
                fi
            else
                local new_func=""
                if new_func=$(select_launch_function_with_retry "$e_app_id"); then
                    e_launch_function="$new_func"
                    modified=true
                    echo "✓ Launch function updated to: $e_launch_function" >&3
                fi
            fi
            ;;
        5)
            echo "" >&3
            echo "Current parameters: ${e_parameters:-<none>}" >&3
            echo "Enter new parameters (press Enter to clear):" >&3
            read -r e_parameters
            modified=true
            echo "✓ Parameters updated" >&3
            ;;
        6)
            debug_function_exit "$function_name"
            return 1
            ;;
        *)
            echo "Invalid choice." >&3
            debug_function_exit "$function_name"
            return 1
            ;;
    esac

    if [[ "$modified" == true ]]; then
        apps_array_ref[$idx]="${e_app_id}|${e_window_name}|${e_launch_function}|${e_desktop}|${e_screen}|${e_position}|${e_parameters}"
    fi

    debug_function_exit "$function_name"
    if [[ "$modified" == true ]]; then
        return 0
    else
        return 1
    fi
}

_edit_save() {
    local workspace_name="$1"
    local description="$2"
    # apps_array_ref="$3"
    local -n apps_array_ref="$3"
    local function_name="_edit_save"

    debug_function_enter "$function_name" "$@"

    # Must have at least one window
    if [[ ${#apps_array_ref[@]} -eq 0 ]]; then
        echo "" >&3
        echo "Error: Workspace must have at least one window." >&3
        echo "Add a window before saving, or cancel to discard changes." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Show final summary
    echo "" >&3
    echo "=== Save Configuration ===" >&3
    _edit_show_summary "$workspace_name" "$description" apps_array_ref
    echo "" >&3
    echo "Save these changes? (y/n)" >&3
    local confirm=""
    read -r confirm

    if [[ "$confirm" != "y" ]]; then
        echo "Save cancelled." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Update description
    echo "" >&3
    echo "Updating workspace..." >&3
    if ! db_update_workspace_description "$workspace_name" "$description"; then
        echo "Error: Failed to update workspace description." >&2
        debug_function_exit "$function_name"
        return 1
    fi
    echo "✓ Workspace metadata updated" >&3

    # Regenerate scripts and window definitions
    echo "Regenerating workspace scripts..." >&3
    if ! generate_workspace_scripts "$workspace_name" apps_array_ref; then
        debug_error "$function_name" "$ERR_SCRIPT_GENERATION_FAILED"
        echo "Error: Failed to regenerate workspace scripts." >&2
        debug_function_exit "$function_name"
        return 1
    fi
    echo "✓ Scripts regenerated successfully" >&3

    echo "" >&3
    echo "================================================================" >&3
    echo "Workspace '$workspace_name' updated successfully!" >&3
    echo "================================================================" >&3
    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}
