#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WORKSPACE_CLOSE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/window-tracking.sh
source "${LIB_DIR}/db/window-tracking.sh"
# shellcheck source=../../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"

workspace_close() {
    local workspace_name="$1"
    local function_name="workspace_close"

    debug_function_enter "$function_name" "$@"

    # Validate workspace name parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        echo "Usage: kdoitall workspace close <workspace-name>" >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # Check if workspace exists in database
    if ! db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Check if workspace is active
    local is_active=""
    is_active=$(db_get_workspace_is_active "$workspace_name")

    if [[ "$is_active" != "1" ]]; then
        echo "Workspace '$workspace_name' is not active. Nothing to close." >&3
        debug_function_exit "$function_name"
        return 1
    fi

    # ======================================================================
    # Phase 1: Close Attempt
    # ======================================================================

    # Save user's currently active window for restoration later
    local saved_active_uuid=""
    saved_active_uuid=$(get_active_window_uuid)

    # Get all tracked windows for this workspace
    local -a window_rows=()
    mapfile -t window_rows < <(db_get_workspace_windows_ordered "$workspace_name")

    # Short-circuit if no tracked windows
    if [[ ${#window_rows[@]} -eq 0 || -z "${window_rows[0]}" ]]; then
        debug_log "$function_name" "No tracked windows for workspace '$workspace_name'"
        db_set_workspace_active "$workspace_name" "FALSE"
        info_log "$function_name" "Workspace '$workspace_name' closed (0 windows)"
        debug_function_exit "$function_name"
        return 0
    fi

    # Send close request for each window
    local window_name=""
    local uuid=""
    local row=""

    for row in "${window_rows[@]}"; do
        IFS='|' read -r window_name uuid <<< "$row"
        close_window "$uuid"
        debug_log "$function_name" "Sent close request: $window_name ($uuid)"
    done

    # Brief settling delay
    sleep "$WINDOW_DELAY"

    # ======================================================================
    # Phase 2: Verification
    # ======================================================================

    refresh_current_windows

    local -a unclosed_windows=()
    local closed_count=0
    local skipped_count=0

    for row in "${window_rows[@]}"; do
        IFS='|' read -r window_name uuid <<< "$row"

        if window_exists "$uuid"; then
            # Window still alive — add to unclosed list
            unclosed_windows+=("$row")
            debug_log "$function_name" "Window still open: $window_name ($uuid)"
        else
            # Window closed successfully — remove from DB
            db_delete_window "$window_name"
            ((closed_count++)) || true
            debug_log "$function_name" "Window closed: $window_name ($uuid)"
        fi
    done

    # ======================================================================
    # Phase 3: Assisted Close
    # ======================================================================

    if [[ ${#unclosed_windows[@]} -gt 0 ]]; then
        local is_interactive=false
        [[ -t 0 ]] && is_interactive=true

        local remaining=0
        remaining=${#unclosed_windows[@]}

        for row in "${unclosed_windows[@]}"; do
            IFS='|' read -r window_name uuid <<< "$row"

            # Bring the window to focus so user can interact with dialog
            activate_window "$uuid"

            info_log "$function_name" "Waiting for window to close: $window_name ($remaining remaining)"

            # Poll loop
            local elapsed=0
            local window_closed=false

            while (( elapsed < CLOSE_WAIT_TIMEOUT )); do
                sleep 1
                ((elapsed++))

                if window_not_exists "$uuid"; then
                    window_closed=true
                    break
                fi
            done

            if [[ "$window_closed" == "true" ]]; then
                # Window closed during poll
                db_delete_window "$window_name"
                ((closed_count++)) || true
                debug_log "$function_name" "Window closed during poll: $window_name ($uuid)"
            else
                # Timeout reached
                local skip=true

                if [[ "$is_interactive" == "true" ]]; then
                    local response=""
                    echo "[s]kip / [r]etry? (auto-skip in 10s): " >&3
                    if read -t 10 response; then
                        if [[ "$response" == "r" || "$response" == "retry" ]]; then
                            skip=false

                            # Retry: reset and re-enter poll loop
                            elapsed=0
                            window_closed=false

                            while (( elapsed < CLOSE_WAIT_TIMEOUT )); do
                                sleep 1
                                ((elapsed++))

                                if window_not_exists "$uuid"; then
                                    window_closed=true
                                    break
                                fi
                            done

                            if [[ "$window_closed" == "true" ]]; then
                                db_delete_window "$window_name"
                                ((closed_count++)) || true
                                debug_log "$function_name" "Window closed during retry: $window_name ($uuid)"
                            else
                                skip=true
                            fi
                        fi
                    fi
                fi

                if [[ "$skip" == "true" ]]; then
                    # Release window to ~workspace
                    db_release_window_to_auto "$window_name"
                    ((skipped_count++)) || true
                    info_log "$function_name" "Skipped window: $window_name"
                    debug_log "$function_name" "Released to ~workspace: $window_name ($uuid)"
                fi
            fi

            ((remaining--)) || true
        done
    fi

    # ======================================================================
    # Phase 4: Cleanup & Restoration
    # ======================================================================

    db_set_workspace_active "$workspace_name" "FALSE"

    # Restore user's previously active window if it still exists
    if [[ -n "$saved_active_uuid" ]]; then
        if ! window_not_exists "$saved_active_uuid"; then
            activate_window "$saved_active_uuid"
        fi
    fi

    info_log "$function_name" "Workspace '$workspace_name' closed ($closed_count closed, $skipped_count skipped)"
    debug_function_exit "$function_name"
    return 0
}
