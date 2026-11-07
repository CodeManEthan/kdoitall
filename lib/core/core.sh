#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_CORE_LOADED" || return 0

# shellcheck source=../window-management/desktop.sh
source "${LIB_DIR}/window-management/desktop.sh"
# shellcheck source=../window-management/screen.sh
source "${LIB_DIR}/window-management/screen.sh"
# shellcheck source=../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"
# shellcheck source=../utils/display.sh
source "${LIB_DIR}/utils/display.sh"

_launch_via_gtk() {
    local target_app_id="$1"

    gtk-launch "$target_app_id" > /dev/null 2>&1 & disown
}

# Prints the title of a window that was just found, or nothing. Always
# returns 0: the window exists, so a failed title read must not fail the
# launch. Right after a window maps, or under load, kdotool can return an
# empty title, so the read is retried briefly. get_window_title's stderr is
# dropped because an empty read is expected here; debug_error still writes
# it to the log file when one is set. Phase 7 reads the title again for
# pattern learning and skips that step when the title is still empty.
_read_title_for_registration() {
    local uuid="$1"
    local title=""
    local attempt=0
    local function_name="_read_title_for_registration"

    debug_function_enter "$function_name" "$@"

    for attempt in 1 2 3; do
        if title=$(get_window_title "$uuid" 2>/dev/null); then
            break
        fi
        title=""
        if [[ "$attempt" -lt 3 ]]; then
            sleep 0.2
        fi
    done

    if [[ -z "$title" ]]; then
        debug_log "$function_name" "No title for $uuid after $attempt reads; registering with an empty title"
    fi

    debug_function_exit "$function_name"
    printf '%s\n' "$title"
    return 0
}

execute_launch_window() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local launch_mode="$7"
    local launch_type="$8"
    local launch_fn="$9"
    local class="${10}"
    local window_title_pattern="${11}"
    local launch_time="${12}"
    local launch_fn_arg="${13:-}"
    local has_splash_window="${14:-}"
    local splash_duration_ms="${15:-}"
    local function_name="execute_launch_window"
    local uuid=""
    local window_title=""
    local detection_method=""
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$desktop" "desktop" || return 1
    validate_parameter_pass "$screen" "screen" || return 1
    validate_parameter_pass "$position" "position" || return 1
    validate_parameter_pass "$launch_mode" "launch_mode" || return 1
    validate_parameter_pass "$launch_type" "launch_type" || return 1
    validate_parameter_pass "$launch_fn" "launch_fn" || return 1

    info_log "$function_name" "Launching $app_id (window: $window_name)"

    # ──────────────────────────────────────────────
    # PHASE 1: PRE-LAUNCH SNAPSHOT
    # ──────────────────────────────────────────────

    debug_log "$function_name" "Phase 1: Pre-launch snapshot"
    auto_detect_windows

    # ──────────────────────────────────────────────
    # PHASE 2: SINGLE-INSTANCE SHORT CIRCUIT
    # ──────────────────────────────────────────────

    if [[ "$launch_mode" == "$LAUNCH_MODE_SINGLE" ]]; then
        debug_log "$function_name" "Phase 2: Single-instance check"
        # With no class and no title pattern yet (an app not learned yet)
        # there is nothing to search by, so launch it fresh.
        if [[ -n "$class" || -n "$window_title_pattern" ]]; then
            uuid=$(get_uuid "$class" "$window_title_pattern")
        else
            debug_log "$function_name" "Phase 2: no class or title pattern known, skipping the existing-window check"
        fi

        if [[ -n "$uuid" ]]; then
            debug_log "$function_name" "Single-instance window already exists: $uuid"
            info_log "$function_name" "Window already open, reclaiming: $uuid"
            window_title=$(_read_title_for_registration "$uuid")
            raise_window "$uuid"
            db_claim_window "$workspace_name" "$window_name" "$uuid" "$window_title"

            # Skip to Phase 6 (position window)
            move_window_to_desktop "$uuid" "$desktop"
            move_window_to_screen "$uuid" "$screen"
            move_window_to_position "$uuid" "$screen" "$position"

            info_log "$function_name" "Positioned on Screen $screen, Desktop $desktop, $position"

            debug_function_exit "$function_name"
            return 0
        fi
    fi

    # ──────────────────────────────────────────────
    # PHASE 3: PREPARE AND LAUNCH
    # ──────────────────────────────────────────────

    debug_log "$function_name" "Phase 3: Prepare and launch"

    # Record active window before launch
    local pre_launch_active_uuid=""
    pre_launch_active_uuid=$(get_active_window_uuid)

    # Check if active window's class matches target class
    local active_matches_target_class="false"
    if [[ -n "$class" && -n "$pre_launch_active_uuid" ]]; then
        local active_class=""
        active_class=$(get_window_class "$pre_launch_active_uuid") || true
        if [[ "$active_class" == "$class" ]]; then
            active_matches_target_class="true"
            debug_log "$function_name" "Active window class matches target class: '$class'"
        fi
    fi

    # Record window count before launch
    local pre_launch_window_count=${#CURRENT_UUIDS[@]}
    debug_log "$function_name" "Pre-launch state: active='$pre_launch_active_uuid', window_count=$pre_launch_window_count"

    # Record start time for launch time measurement
    local launch_start_ms=""
    launch_start_ms=$(date +%s%3N)

    # Launch the application
    debug_log "$function_name" "Launching via: $launch_fn${launch_fn_arg:+ (arg: $launch_fn_arg)}"
    "$launch_fn" "$launch_fn_arg"

    # ──────────────────────────────────────────────
    # PHASE 4: DETECT WINDOW (observe what happened)
    # ──────────────────────────────────────────────

    debug_log "$function_name" "Phase 4: Detect window"

    # Brief pause to let the launch command take effect
    sleep "$LAUNCH_DELAY"

    # --- Capture post-launch snapshot once, before mode-specific detection ---
    local current_active_uuid=""
    current_active_uuid=$(get_active_window_uuid)

    get_existing_windows_uuid
    local current_window_count=${#CURRENT_UUIDS[@]}

    debug_log "$function_name" "Post-launch state: active='$current_active_uuid', window_count=$current_window_count"

    if [[ "$launch_mode" == "$LAUNCH_MODE_SINGLE_OR_UNIQUE" || "$launch_mode" == "$LAUNCH_MODE_UNKNOWN" ]]; then
        # Apps that may or may not allow multiple instances:
        # Try process of elimination first (give the app a chance to create a new window),
        # then fall back to existing window detection if no new window appeared.

        debug_log "$function_name" "Detection order: process of elimination → quick check → fallback (mode: $launch_mode)"

        # --- Process of elimination: wait for a new window to appear ---
        debug_log "$function_name" "Trying process of elimination first"
        uuid=$(get_uuid_by_process_of_elimination_with_retry "$class" 5000 100) || true

        if [[ -n "$uuid" ]]; then
            detection_method="new_window"
            debug_log "$function_name" "Process of elimination found new window: $uuid"
        fi

        # --- Quick check: did the app focus an existing window? ---
        if [[ -z "$uuid" ]]; then
            debug_log "$function_name" "No new window, checking if app focused an existing window"

            if [[ -n "$current_active_uuid" && "$current_active_uuid" != "$pre_launch_active_uuid" && "$current_window_count" -eq "$pre_launch_window_count" ]]; then
                debug_log "$function_name" "Active window changed, no new windows — checking existing window focus"

                if [[ "$active_matches_target_class" == "true" ]]; then
                    local current_active_class=""
                    current_active_class=$(get_window_class "$current_active_uuid") || true

                    if [[ "$current_active_class" == "$class" ]]; then
                        uuid="$current_active_uuid"
                        detection_method="existing_window"
                        debug_log "$function_name" "App focused different existing window of same class: $uuid"
                    else
                        uuid="$pre_launch_active_uuid"
                        detection_method="existing_window"
                        debug_log "$function_name" "App toggled active window, reclaiming: $uuid"
                    fi
                elif [[ -n "$class" ]]; then
                    local current_active_class=""
                    current_active_class=$(get_window_class "$current_active_uuid") || true

                    if [[ "$current_active_class" == "$class" ]]; then
                        uuid="$current_active_uuid"
                        detection_method="existing_window"
                        debug_log "$function_name" "App focused existing window with target class: $uuid"
                    fi
                fi
            fi
        fi

        # --- Final fallback: class/title search ---
        if [[ -z "$uuid" && -n "$class" ]]; then
            debug_log "$function_name" "Quick check failed, trying class/title fallback"
            uuid=$(get_uuid "$class" "$window_title_pattern") || true

            if [[ -n "$uuid" ]]; then
                detection_method="existing_window"
                debug_log "$function_name" "Fallback found window: $uuid"
            fi
        fi

    else
        # MULTI / UNIQUE modes:
        # Try quick check first (existing window focus), then process of elimination.

        debug_log "$function_name" "Detection order: quick check → process of elimination → fallback (mode: $launch_mode)"

        # --- Quick check: did the app focus an existing window? ---
        if [[ -n "$current_active_uuid" && "$current_active_uuid" != "$pre_launch_active_uuid" && "$current_window_count" -eq "$pre_launch_window_count" ]]; then
            debug_log "$function_name" "Active window changed, no new windows — checking existing window focus"

            if [[ "$active_matches_target_class" == "true" ]]; then
                local current_active_class=""
                current_active_class=$(get_window_class "$current_active_uuid") || true

                if [[ "$current_active_class" == "$class" ]]; then
                    uuid="$current_active_uuid"
                    detection_method="existing_window"
                    debug_log "$function_name" "App focused different existing window of same class: $uuid"
                else
                    uuid="$pre_launch_active_uuid"
                    detection_method="existing_window"
                    debug_log "$function_name" "App toggled active window, reclaiming: $uuid"
                fi
            elif [[ -n "$class" ]]; then
                local current_active_class=""
                current_active_class=$(get_window_class "$current_active_uuid") || true

                if [[ "$current_active_class" == "$class" ]]; then
                    uuid="$current_active_uuid"
                    detection_method="existing_window"
                    debug_log "$function_name" "App focused existing window with target class: $uuid"
                fi
            fi
        fi

        # --- Process of elimination: wait for a new window to appear ---
        if [[ -z "$uuid" ]]; then
            debug_log "$function_name" "Quick check did not find existing window, trying process of elimination"
            uuid=$(get_uuid_by_process_of_elimination_with_retry "$class" 5000 100) || true

            if [[ -n "$uuid" ]]; then
                detection_method="new_window"
                debug_log "$function_name" "Process of elimination found new window: $uuid"
            fi
        fi

        # --- Final fallback: class/title search ---
        if [[ -z "$uuid" && -n "$class" ]]; then
            debug_log "$function_name" "Process of elimination failed, trying class/title fallback"
            uuid=$(get_uuid "$class" "$window_title_pattern") || true

            if [[ -n "$uuid" ]]; then
                detection_method="existing_window"
                debug_log "$function_name" "Fallback found window: $uuid"
            fi
        fi
    fi

    # ──────────────────────────────────────────────
    # PHASE 4b: SPLASH WINDOW STABILITY CHECK
    # ──────────────────────────────────────────────

    if [[ -n "$uuid" && "$detection_method" == "new_window" && -n "$has_splash_window" && "$has_splash_window" != "false" ]]; then
        debug_log "$function_name" "Phase 4b: Splash stability check (has_splash_window=$has_splash_window)"

        local splash_max_wait_ms=""
        local splash_check_interval_ms=500
        local splash_stability_threshold=3
        local splash_min_monitor_ms=0

        if [[ "$has_splash_window" == "true" ]]; then
            # Known splash app — wait past measured splash duration before
            # accepting stability. Grace period handles flickers; min_monitor
            # prevents premature acceptance of the splash itself.
            if [[ -n "$splash_duration_ms" && "$splash_duration_ms" -gt 0 ]]; then
                splash_max_wait_ms=$(( splash_duration_ms * 2 + 3000 ))
                splash_min_monitor_ms="$splash_duration_ms"
            elif [[ -n "$launch_time" && "$launch_time" -gt 0 ]]; then
                splash_max_wait_ms=$(( launch_time * 3 ))
                splash_min_monitor_ms="$launch_time"
            else
                splash_max_wait_ms=15000
                splash_min_monitor_ms=5000
            fi
        else
            # Unknown — defer stability declaration past common splash
            # durations so apps like digiKam (~2.8s splash) get caught by
            # the splash-recovery flow. Without min_monitor_ms, stability
            # was being declared after ~1s while the splash was still alive,
            # so the splash UUID was returned and the recovery flow never
            # ran. See docs/flows/window-launch-pipeline.md Phase 4b.
            splash_max_wait_ms=6000
            splash_min_monitor_ms=3000
            splash_stability_threshold=2
        fi

        debug_log "$function_name" "Phase 4b: wait_for_stable_window (max_wait=${splash_max_wait_ms}ms, interval=${splash_check_interval_ms}ms, threshold=$splash_stability_threshold, min_monitor=${splash_min_monitor_ms}ms)"

        local splash_result=""
        splash_result=$(wait_for_stable_window "$uuid" "$splash_max_wait_ms" "$splash_check_interval_ms" "$splash_stability_threshold" "$splash_min_monitor_ms") || true

        if [[ -n "$splash_result" ]]; then
            local stable_uuid=""
            local splash_was_detected=""
            local measured_splash_duration_ms=""
            IFS='|' read -r stable_uuid splash_was_detected measured_splash_duration_ms <<< "$splash_result"

            if [[ -n "$stable_uuid" && "$stable_uuid" != "$uuid" ]]; then
                debug_log "$function_name" "Phase 4b: UUID changed from '$uuid' to '$stable_uuid' — re-syncing"
                uuid="$stable_uuid"
                # Refresh CURRENT_UUIDS to reflect the new window. Do NOT
                # call auto_detect_windows here — its db_add_existing_windows
                # step would insert the new UUID into app_windows, then
                # Phase 5's db_add_window would hit the UNIQUE constraint
                # on uuid. wait_for_stable_window already cleaned up the
                # dead splash UUID via its own refresh+delete-stale pass.
                refresh_current_windows
            fi

            # Auto-learn: if unknown and splash detected, mark as splash app
            # and record the measured duration so future launches can use
            # min_monitor_ms tuned to this app rather than the generic 3s.
            if [[ "$has_splash_window" == "unknown" && "$splash_was_detected" == "true" ]]; then
                debug_log "$function_name" "Phase 4b: Auto-learning — setting has_splash_window=true (duration=${measured_splash_duration_ms}ms) for $app_id"
                db_set_has_splash_window "$app_id" "true" "$measured_splash_duration_ms"
            fi
        fi
    fi

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_NOT_FOUND" "Could not detect window for app_id: $app_id"
        info_log "$function_name" "Window detection failed for $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    info_log "$function_name" "Window detected: $uuid (method: $detection_method)"

    # Record launch elapsed time (before registration, as close to detection as possible)
    local launch_elapsed_ms=""
    launch_elapsed_ms=$(( $(date +%s%3N) - launch_start_ms ))

    # ──────────────────────────────────────────────
    # PHASE 5: REGISTER WINDOW
    # ──────────────────────────────────────────────

    debug_log "$function_name" "Phase 5: Register window (detection_method=$detection_method)"
    window_title=$(_read_title_for_registration "$uuid")

    if [[ "$detection_method" == "new_window" ]]; then
        # Fresh launch — new window appeared
        if [[ -n "$app_id" && -z "$class" ]]; then
            class=$(detect_and_store_class "$uuid" "$app_id")
        fi

        db_add_window "$workspace_name" "$window_name" "$uuid" "$class" "$window_title"
    else
        # Focused existing window
        raise_window "$uuid"
        db_claim_window "$workspace_name" "$window_name" "$uuid" "$window_title"
        launch_elapsed_ms=""  # Not a real launch, don't record timing
    fi

    # ──────────────────────────────────────────────
    # PHASE 6: POSITION WINDOW
    # ──────────────────────────────────────────────

    debug_log "$function_name" "Phase 6: Position window"
    move_window_to_desktop "$uuid" "$desktop"
    move_window_to_screen "$uuid" "$screen"
    move_window_to_position "$uuid" "$screen" "$position"

    info_log "$function_name" "Positioned on Screen $screen, Desktop $desktop, $position"

    # ──────────────────────────────────────────────
    # PHASE 7: BACKGROUND DATA GATHERING
    # ──────────────────────────────────────────────

    debug_log "$function_name" "Phase 7: Background data gathering"
    gather_post_launch_metadata "$app_id" "$uuid" "$launch_elapsed_ms"

    debug_function_exit "$function_name"
}

gather_post_launch_metadata() {
    local app_id="$1"
    local uuid="$2"
    local launch_elapsed_ms="$3"
    local function_name="gather_post_launch_metadata"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 0
    validate_parameter_pass "$uuid" "uuid" || return 0

    # Single DB query to check what metadata is already populated
    local metadata_status=""
    metadata_status=$(db_get_app_metadata_status "$app_id") || {
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to get metadata status for $app_id"
        debug_function_exit "$function_name"
        return 0
    }

    local existing_pid_status=""
    local existing_title_pattern=""
    local display_name=""
    local stored_class=""
    local current_launch_time_ms=""
    local current_launch_time_samples=""
    IFS='|' read -r existing_pid_status existing_title_pattern display_name stored_class \
        current_launch_time_ms current_launch_time_samples <<< "$metadata_status"

    debug_log "$function_name" "Existing metadata — pid_status: '$existing_pid_status', title_pattern: '$existing_title_pattern', launch_time_ms: '$current_launch_time_ms', samples: '$current_launch_time_samples'"

    # ── Gather missing data in memory ──

    # PID validation data
    local new_supports_pid=""
    local new_process_name=""
    local new_exe_path=""

    if [[ -z "$existing_pid_status" ]]; then
        debug_log "$function_name" "Gathering PID validation data"
        local pid=""
        pid=$(get_window_pid "$uuid") || true

        if [[ -n "$pid" ]]; then
            new_process_name=$(get_process_name "$pid" 2>/dev/null) || true
            new_exe_path=$(get_executable_path "$pid" 2>/dev/null) || true

            if [[ -n "$new_process_name" ]]; then
                new_supports_pid="1"
                debug_log "$function_name" "PID validation: supports=true, process='$new_process_name', path='$new_exe_path'"
            else
                new_supports_pid="0"
                debug_log "$function_name" "PID validation: supports=false (no process name)"
            fi
        else
            new_supports_pid="0"
            debug_log "$function_name" "PID validation: supports=false (no PID)"
        fi
    fi

    # Window title pattern
    local new_title_pattern=""

    if [[ -z "$existing_title_pattern" ]]; then
        debug_log "$function_name" "Gathering window title pattern"
        local title=""
        title=$(get_window_title "$uuid") || true

        if [[ -n "$title" ]]; then
            new_title_pattern=$(auto_select_title_pattern "$title" "$display_name" "$stored_class") || true
            if [[ -n "$new_title_pattern" ]]; then
                debug_log "$function_name" "Auto-selected title pattern: '$new_title_pattern'"
            fi
        fi
    fi

    # Launch time (rolling average calculation)
    local new_expected_time=""
    local new_measured_time=""

    if [[ -n "$launch_elapsed_ms" ]]; then
        new_measured_time="$launch_elapsed_ms"
        debug_log "$function_name" "Measured launch time: ${launch_elapsed_ms}ms"

        if [[ "$current_launch_time_samples" -eq 0 || "$current_launch_time_ms" -eq 0 ]]; then
            # First sample: use measured time + 50% buffer
            new_expected_time=$(( launch_elapsed_ms * 3 / 2 ))
        else
            # Rolling average: (current_avg * samples + new) / (samples + 1)
            local avg=$(( (current_launch_time_ms * current_launch_time_samples + launch_elapsed_ms) / (current_launch_time_samples + 1) ))
            # Add 25% buffer
            new_expected_time=$(( avg * 5 / 4 ))
        fi

        debug_log "$function_name" "Computed expected launch time: ${new_expected_time}ms"
    fi

    # ── Single DB update if anything new was gathered ──

    if [[ -n "$new_supports_pid" || -n "$new_title_pattern" || -n "$new_measured_time" ]]; then
        debug_log "$function_name" "Writing post-launch metadata to database"
        db_set_post_launch_metadata "$app_id" \
            "$new_supports_pid" "$new_process_name" "$new_exe_path" \
            "$new_title_pattern" "$new_expected_time" "$new_measured_time" || {
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to set post-launch metadata for $app_id"
        }
    else
        debug_log "$function_name" "No new metadata to write"
    fi

    debug_function_exit "$function_name"
    return 0
}

execute_close_window() {
    local window_name="$1"
    local uuid=""
    local function_name="execute_close_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$window_name" "window_name" || return 1

    uuid=$(db_get_uuid "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    close_window "$uuid"

    db_delete_window "$window_name"

    debug_function_exit "$function_name"
}

auto_detect_windows() {
    local function_name="auto_detect_windows"

    debug_function_enter "$function_name"
    
    debug_log "$function_name" "===== REFRESH CURRENT WINDOWS ====="
    refresh_current_windows

    debug_log "$function_name" "===== GET DATA FROM DATABASE ====="
    db_get_all_windows

    debug_log "$function_name" "===== KDOTOOL RESULTS ====="
    debug_array CURRENT_UUIDS
    debug_array CURRENT_CLASSES
    debug_array CURRENT_TITLES
    
    debug_log "$function_name" "===== DATABASE RESULTS ====="
    debug_array DB_UUIDS
    debug_array DB_CLASSES
    debug_array DB_TITLES

    # Per-UUID verification: protect live windows that may have been
    # truncated out of CURRENT_UUIDS by the kdotool DBus race before
    # letting db_delete_stale_windows operate on the snapshot.
    debug_log "$function_name" "===== VERIFY STALE CANDIDATES ====="
    _verify_stale_candidates

    # Final safety net: if the snapshot is empty even after per-UUID
    # verification while the DB has tracked windows, every kdotool query
    # has failed — skip cleanup to preserve DB state.
    if [[ ${#CURRENT_UUIDS[@]} -eq 0 && ${#DB_UUIDS[@]} -gt 0 ]]; then
        debug_log "$function_name" "Empty snapshot post-verification with ${#DB_UUIDS[@]} tracked windows — skipping stale cleanup"
    else
        debug_log "$function_name" "===== DELETE STALE WINDOWS ====="
        db_delete_stale_windows
    fi
    
    debug_log "$function_name" "===== ADD NEW WINDOWS ====="
    db_add_existing_windows

    debug_function_exit "$function_name"
}

launch_by_app_id() {
    local workspace_name="$1"
    local window_name="$2"
    local app_id="$3"
    local desktop="$4"
    local screen="$5"
    local position="$6"
    local launch_mode=""
    local launch_type=""
    local class=""
    local window_title_pattern=""
    local launch_time=""
    local has_splash_window=""
    local function_name="launch_by_app_id"

    debug_function_enter "$function_name"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$window_name" "window_name" || return 1
    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$desktop" "desktop" || return 1
    validate_parameter_pass "$screen" "screen" || return 1
    validate_parameter_pass "$position" "position" || return 1

    validate_app_id_format "$app_id" || return 1

    launch_type="$LAUNCH_TYPE_DESKTOP"

    debug_log "$function_name" "Obtain application properties from database."

    local launch_properties=""
    launch_properties=$(db_get_app_launch_properties "$app_id")

    if [[ -z "$launch_properties" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi

    IFS='|' read -r class window_title_pattern launch_mode launch_time has_splash_window splash_duration_ms <<< "$launch_properties"

    if [[ -z "$launch_mode" ]]; then
        launch_mode="$LAUNCH_MODE_UNKNOWN"
    fi

     execute_launch_window \
     "$workspace_name" "$window_name" "$app_id" "$desktop" "$screen" "$position" \
     "$launch_mode" "$launch_type" "_launch_via_gtk" "$class" "$window_title_pattern" "$launch_time" "$app_id" "$has_splash_window" "$splash_duration_ms"

     debug_function_exit "$function_name"
}

detect_and_store_class() {
    local uuid="$1"
    local app_id="$2"
    local function_name="detect_and_store_class"
    
    debug_function_enter "$function_name" "$@"
    debug_log "$function_name" "Detecting app_class for $app_id..."
    
    # Detect actual window class from the launched window
    local detected_class=""
    detected_class=$(get_window_class "$uuid")
    
    if [[ -n "$detected_class" ]]; then
        # Store in database for future use
        if db_set_app_class "$app_id" "$detected_class"; then
            debug_log "$function_name" "✓ Auto-detected and stored app_class: $detected_class"
            debug_function_exit "$function_name"
            echo "$detected_class"
            return 0
        else
            debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to store app_class: $detected_class"
            debug_function_exit "$function_name"
            return 1
        fi
    else
        debug_error "$function_name" "$ERR_WINDOW_CLASS_NOT_FOUND" "Could not detect class for UUID $uuid"
        debug_function_exit "$function_name"
        return 1
    fi
}
