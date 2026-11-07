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
# shellcheck source=../../utils/colors.sh
source "${LIB_DIR}/utils/colors.sh"
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

    # Prevent editing an active workspace
    local is_active=""
    is_active=$(db_get_workspace_is_active "$workspace_name")
    if [[ "$is_active" == "1" ]]; then
        echo "Error: Cannot edit workspace '$workspace_name' while it is active." >&2
        echo "Close the workspace first with: kdoitall workspace close $workspace_name" >&3
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_IS_ACTIVE"
    fi

    # Load current workspace metadata
    local workspace_data=""
    workspace_data=$(db_get_workspace "$workspace_name")
    IFS='|' read -r _ description _ _ _ <<< "$workspace_data"

    # Load current window definitions into WORKSPACE_APPS array
    if ! _edit_load_window_definitions "$workspace_name"; then
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    print_header "Editing workspace: $workspace_name"

    # Main edit loop
    while true; do
        echo "" >&3
        _edit_show_summary "$workspace_name" "$description"
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
                    print_success "Description updated"
                fi
                ;;
            2)
                local display_order=${#WORKSPACE_APPS[@]}
                ((display_order++))

                echo "" >&3
                print_header "Add Application to Workspace"
                echo "" >&3

                if add_application_to_workspace "$workspace_name" "$display_order" WORKSPACE_APPS; then
                    has_changes=true
                else
                    print_warning "Application addition cancelled."
                fi
                ;;
            3)
                if _edit_window "$workspace_name"; then
                    has_changes=true
                fi
                ;;
            4)
                if _edit_remove_window; then
                    has_changes=true
                fi
                ;;
            5)
                if [[ "$has_changes" != true ]]; then
                    echo "" >&3
                    print_warning "No changes to save."
                    continue
                fi

                if _edit_save "$workspace_name" "$description"; then
                    debug_function_exit "$function_name"
                    return 0
                fi
                ;;
            6)
                if [[ "$has_changes" == true ]]; then
                    echo "" >&3
                    print_warning "You have unsaved changes. Discard and exit? (y/n)"
                    local confirm_cancel=""
                    read -r confirm_cancel

                    if [[ "$confirm_cancel" != "y" ]]; then
                        continue
                    fi
                fi

                print_info "Edit cancelled."
                debug_function_exit "$function_name"
                return 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-6."
                ;;
        esac
    done
}

_edit_load_window_definitions() {
    local workspace_name="$1"

    # Delegate to shared helper in generator.sh
    load_workspace_apps_array "$workspace_name"
}

_edit_show_summary() {
    local workspace_name="$1"
    local description="$2"

    print_header "Current Configuration"
    echo "Workspace: $workspace_name" >&3
    echo "Description: ${description:-<none>}" >&3
    echo "" >&3

    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        echo "Windows: (none)" >&3
        return 0
    fi

    echo "Windows (${#WORKSPACE_APPS[@]}):" >&3

    local idx=0
    local app_entry=""
    for app_entry in "${WORKSPACE_APPS[@]}"; do
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
    print_prompt "Edit Options:"
    echo "  1) Edit description" >&3
    echo "  2) Add window" >&3
    echo "  3) Edit window" >&3
    echo "  4) Remove window" >&3
    echo "  5) Save and apply changes" >&3
    echo "  6) Cancel" >&3
    echo "" >&3
    print_prompt "Select option (1-6):"
}

_edit_remove_window() {
    local function_name="_edit_remove_window"

    debug_function_enter "$function_name"

    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        print_warning "No windows to remove."
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    print_prompt "Select window to remove (1-${#WORKSPACE_APPS[@]}, or 'c' to cancel):"
    local selection=""
    read -r selection

    if [[ "$selection" == "c" ]]; then
        debug_function_exit "$function_name"
        return 1
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [[ "$selection" -lt 1 ]] || \
       [[ "$selection" -gt ${#WORKSPACE_APPS[@]} ]]; then
        print_error "Invalid selection."
        debug_function_exit "$function_name"
        return 1
    fi

    local idx=$((selection - 1))
    local removed_entry="${WORKSPACE_APPS[$idx]}"
    local removed_name=""
    removed_name=$(echo "$removed_entry" | cut -d'|' -f2)

    # Remove element from array
    unset 'WORKSPACE_APPS[idx]'
    # Re-index to close the gap
    WORKSPACE_APPS=("${WORKSPACE_APPS[@]}")

    print_success "Removed window: $removed_name"

    debug_function_exit "$function_name"
    return 0
}

_edit_window() {
    local workspace_name="$1"
    local function_name="_edit_window"

    debug_function_enter "$function_name"

    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        print_warning "No windows to edit."
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    print_prompt "Select window to edit (1-${#WORKSPACE_APPS[@]}, or 'c' to cancel):"
    local selection=""
    read -r selection

    if [[ "$selection" == "c" ]]; then
        debug_function_exit "$function_name"
        return 1
    fi

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [[ "$selection" -lt 1 ]] || \
       [[ "$selection" -gt ${#WORKSPACE_APPS[@]} ]]; then
        print_error "Invalid selection."
        debug_function_exit "$function_name"
        return 1
    fi

    local idx=$((selection - 1))
    local entry="${WORKSPACE_APPS[$idx]}"
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
    print_header "Editing window: $e_window_name ($e_display_name)"
    echo "  Window name:     $e_window_name" >&3
    echo "  Desktop:         $e_desktop" >&3
    echo "  Screen:          $e_screen" >&3
    echo "  Position:        $e_position" >&3
    echo "  Launch function: $e_launch_function" >&3
    echo "  Parameters:      ${e_parameters:-<none>}" >&3
    echo "" >&3
    print_prompt "What would you like to change?"
    echo "  1) Window name" >&3
    echo "  2) Desktop" >&3
    echo "  3) Screen" >&3
    echo "  4) Position" >&3
    echo "  5) Launch function" >&3
    echo "  6) Parameters" >&3
    echo "  7) Cancel" >&3
    echo "" >&3
    print_prompt "Select option (1-7):"

    local edit_choice=""
    read -r edit_choice

    case "$edit_choice" in
        1)
            echo "" >&3
            echo "Current window name: $e_window_name" >&3
            print_prompt "Enter new window name (press Enter to keep current):"
            local new_window_name=""
            read -r new_window_name

            if [[ -n "$new_window_name" && "$new_window_name" != "$e_window_name" ]]; then
                if ! validate_window_name "$new_window_name"; then
                    print_error "Invalid window name."
                elif ! validate_window_name_unique "$new_window_name" WORKSPACE_APPS; then
                    print_warning "Window name not changed."
                elif db_window_definition_exists "$new_window_name"; then
                    print_warning "Window name already in use by another workspace: $new_window_name"
                    print_warning "Window name not changed."
                else
                    e_window_name="$new_window_name"
                    modified=true
                    print_success "Window name updated to: $e_window_name"
                fi
            fi
            ;;
        2)
            local new_desktop=""
            if new_desktop=$(select_desktop_with_retry); then
                e_desktop="$new_desktop"
                modified=true
                print_success "Desktop updated to: $e_desktop"
            fi
            ;;
        3)
            local new_screen=""
            if new_screen=$(select_screen_with_retry); then
                e_screen="$new_screen"
                modified=true
                print_success "Screen updated to: $e_screen"
            fi
            ;;
        4)
            local new_position=""
            if new_position=$(select_position_with_retry); then
                e_position="$new_position"
                modified=true
                print_success "Position updated to: $e_position"
            fi
            ;;
        5)
            if [[ "$e_launch_function" == "launch_by_app_id" ]]; then
                echo "" >&3
                echo "This window uses desktop launch (launch_by_app_id)." >&3
                echo "To change launch function, the app must support terminal launch." >&3

                local app_info_ef=""
                app_info_ef=$(db_get_application "$e_app_id")
                local has_terminal_ef=""
                has_terminal_ef=$(echo "$app_info_ef" | cut -d'|' -f8)

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
                            print_success "Launch function updated to: $e_launch_function"
                        fi
                    fi
                fi
            else
                local new_func=""
                if new_func=$(select_launch_function_with_retry "$e_app_id"); then
                    e_launch_function="$new_func"
                    modified=true
                    print_success "Launch function updated to: $e_launch_function"
                fi
            fi
            ;;
        6)
            echo "" >&3
            echo "Current parameters: ${e_parameters:-<none>}" >&3
            echo "Enter new parameters (press Enter to clear):" >&3
            local new_parameters=""
            read -r new_parameters
            if ! validate_params "$new_parameters"; then
                print_error "Parameters must not contain '|' or control characters."
                debug_function_exit "$function_name"
                return 1
            fi
            e_parameters="$new_parameters"
            modified=true
            print_success "Parameters updated"
            ;;
        7)
            debug_function_exit "$function_name"
            return 1
            ;;
        *)
            print_error "Invalid choice."
            debug_function_exit "$function_name"
            return 1
            ;;
    esac

    if [[ "$modified" == true ]]; then
        WORKSPACE_APPS[$idx]="${e_app_id}|${e_window_name}|${e_launch_function}|${e_desktop}|${e_screen}|${e_position}|${e_parameters}"
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
    local function_name="_edit_save"

    debug_function_enter "$function_name" "$@"

    # Must have at least one window
    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        echo "" >&3
        print_error "Workspace must have at least one window."
        print_info "Add a window before saving, or cancel to discard changes."
        debug_function_exit "$function_name"
        return 1
    fi

    # Show final summary
    echo "" >&3
    print_header "Save Configuration"
    _edit_show_summary "$workspace_name" "$description"
    echo "" >&3
    print_prompt "Save these changes? (y/n)"
    local confirm=""
    read -r confirm

    if [[ "$confirm" != "y" ]]; then
        print_warning "Save cancelled."
        debug_function_exit "$function_name"
        return 1
    fi

    echo "" >&3
    print_info "Updating workspace..."
    if ! db_update_workspace_description "$workspace_name" "$description"; then
        echo "Error: Failed to update workspace description." >&2
        debug_function_exit "$function_name"
        return 1
    fi
    print_success "Workspace metadata updated"

    # Regenerate scripts and window definitions
    print_info "Regenerating workspace scripts..."
    if ! generate_workspace_scripts "$workspace_name"; then
        debug_error "$function_name" "$ERR_SCRIPT_GENERATION_FAILED"
        echo "Error: Failed to regenerate workspace scripts." >&2
        debug_function_exit "$function_name"
        return 1
    fi
    print_success "Scripts regenerated successfully"

    echo "" >&3
    print_banner "Workspace '$workspace_name' updated successfully!"
    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}

workspace_edit_noninteractive() {
    local workspace_name="$1"
    local new_description="${2:-}"
    local has_description_flag="$3"
    local has_focus_window_flag="$4"
    local focus_window_value="${5:-}"
    local function_name="workspace_edit_noninteractive"

    debug_function_enter "$function_name" "$@"

    # ──────────────────────────────────────────────
    # Validate workspace
    # ──────────────────────────────────────────────

    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name is required." >&2
        echo "Usage: kdoitall workspace edit <workspace-name> [--description \"...\"] [--focus-window \"...\"]" >&3
        debug_function_exit "$function_name"
        return "$ERR_MISSING_PARAMETER"
    fi

    if ! db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' not found." >&2
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_NOT_FOUND"
    fi

    local is_active=""
    is_active=$(db_get_workspace_is_active "$workspace_name")
    if [[ "$is_active" == "1" ]]; then
        echo "Error: Cannot edit workspace '$workspace_name' while it is active." >&2
        echo "Close the workspace first with: kdoitall workspace close $workspace_name" >&3
        debug_function_exit "$function_name"
        return "$ERR_WORKSPACE_IS_ACTIVE"
    fi

    # ──────────────────────────────────────────────
    # Apply changes
    # ──────────────────────────────────────────────

    local changes_made=false

    # Update description
    if [[ "$has_description_flag" == true ]]; then
        if ! db_update_workspace_description "$workspace_name" "$new_description"; then
            echo "Error: Failed to update workspace description." >&2
            debug_function_exit "$function_name"
            return 1
        fi
        if [[ -n "$new_description" ]]; then
            print_success "Description updated to: $new_description"
        else
            print_success "Description cleared."
        fi
        changes_made=true
    fi

    # Update focus window
    if [[ "$has_focus_window_flag" == true ]]; then
        if [[ -z "$focus_window_value" ]]; then
            # Clear focus window
            if ! db_set_workspace_focus_window "$workspace_name" ""; then
                echo "Error: Failed to clear focus window." >&2
                debug_function_exit "$function_name"
                return 1
            fi
            print_success "Focus window cleared."
            changes_made=true
        else
            # Validate window exists in this workspace
            if ! db_window_definition_exists "$focus_window_value"; then
                echo "Error: Window '$focus_window_value' not found." >&2
                debug_function_exit "$function_name"
                return "$ERR_WINDOW_DEFINITION_NOT_FOUND"
            fi

            local focus_def=""
            focus_def=$(db_get_window_definition "$focus_window_value")
            local focus_workspace=""
            focus_workspace=$(echo "$focus_def" | cut -d'|' -f2)

            if [[ "$focus_workspace" != "$workspace_name" ]]; then
                echo "Error: Window '$focus_window_value' belongs to workspace '$focus_workspace', not '$workspace_name'." >&2
                debug_function_exit "$function_name"
                return 1
            fi

            if ! db_set_workspace_focus_window "$workspace_name" "$focus_window_value"; then
                echo "Error: Failed to set focus window." >&2
                debug_function_exit "$function_name"
                return 1
            fi
            print_success "Focus window set to '$focus_window_value'."
            changes_made=true
        fi
    fi

    if [[ "$changes_made" != true ]]; then
        print_warning "No changes applied."
    fi

    echo "" >&3

    debug_function_exit "$function_name"
    return 0
}
