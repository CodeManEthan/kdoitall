#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_WINDOW_LOADED" || return 0

# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"
# shellcheck source=./snapshot.sh
source "${LIB_DIR}/window-management/snapshot.sh"

CURRENT_UUIDS=()
CURRENT_CLASSES=()
CURRENT_TITLES=()
declare -gA EXCLUDED_UUIDS=()

# kdotool's KWin script emits each window UUID as a separate asynchronous DBus
# signal, then returns. kdotool's main thread reads accumulated messages
# immediately, but messages emitted near the end of iteration may still be in
# flight — so a `kdotool search` response can be empty (all messages still in
# flight) or a prefix-subset of truth (tail still in flight). See
# docs/flows/window-detection.md edge case #9.
#
# This wrapper addresses the *empty* case only: up to two 50ms re-polls catch
# the all-in-flight transient. The first retry alone catches the common case
# (~3% transient rate becomes ~0%); the second retry catches the rarer case
# where the kdotool DBus stall lasts longer than one retry interval (~0.37%
# becomes ~0.01%). Cost only fires when the previous attempt was empty, so
# the common case is unchanged.
#
# Partial responses (non-empty but truncated) are NOT compensated here
# because masking them at this layer either adds latency to the launch hot
# path (convergence loops) or risks emitting phantom UUIDs of just-closed
# windows (union fallback). Partial responses are handled by caller-side
# validation at destructive call sites (e.g., db_delete_stale_windows via
# _verify_stale_candidates) and by the existing POE retry loop's natural
# resilience to transient incomplete snapshots. The empty-snapshot guard in
# wait_for_stable_window provides an additional defense for the splash-
# recovery DB cleanup path.
_kdotool_search_safe() {
    local out=""
    out=$(kdotool search "$@" 2>/dev/null) || return $?
    if [[ -z "$out" ]]; then
        sleep 0.05
        out=$(kdotool search "$@" 2>/dev/null) || return $?
        if [[ -z "$out" ]]; then
            sleep 0.05
            out=$(kdotool search "$@" 2>/dev/null) || return $?
        fi
    fi
    # Suppress trailing newline when output is genuinely empty so mapfile -t
    # produces 0 elements rather than a single empty-string element.
    [[ -n "$out" ]] && printf '%s\n' "$out"
    return 0
}

_kdotool_getactivewindow_safe() {
    local out=""
    out=$(kdotool getactivewindow 2>/dev/null) || return $?
    if [[ -z "$out" ]]; then
        sleep 0.05
        out=$(kdotool getactivewindow 2>/dev/null) || return $?
        if [[ -z "$out" ]]; then
            sleep 0.05
            out=$(kdotool getactivewindow 2>/dev/null) || return $?
        fi
    fi
    [[ -n "$out" ]] && printf '%s\n' "$out"
    return 0
}

is_transient_window() {
    local uuid="$1"
    local class=""
    local title=""
    local system_class=""
    local function_name="is_transient_window"

    debug_function_enter "$function_name" "$@"

    # Get live window properties (not from DB)
    class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
    title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""

    # Check against system window class blocklist
    for system_class in "${SYSTEM_WINDOW_CLASSES[@]}"; do
        if [[ "$class" == "$system_class" ]]; then
            debug_log "$function_name" "UUID '$uuid' matches blocklisted class '$class'"
            debug_function_exit "$function_name"
            return 0
        fi
    done

    # Reject windows with no class or no title (uninitialized/auxiliary/destruction artifacts)
    if [[ -z "$class" || -z "$title" ]]; then
        debug_log "$function_name" "UUID '$uuid' has empty class or title (class='${class:-}', title='${title:-}')"
        debug_function_exit "$function_name"
        return 0
    fi

    debug_log "$function_name" "UUID '$uuid' is not transient (class='$class', title='$title')"
    debug_function_exit "$function_name"
    return 1
}

wait_for_stable_window() {
    local candidate_uuid="$1"
    local max_wait_ms="${2:-15000}"
    local check_interval_ms="${3:-500}"
    local stability_threshold="${4:-3}"
    local min_monitor_ms="${5:-0}"
    local function_name="wait_for_stable_window"
    local stable_count=0
    local elapsed_ms=0
    local splash_detected="false"
    local splash_duration_ms=""
    local check_result=""
    local dead_uuids=""

    # Grace period: tolerate brief window disappearances (flickers) before
    # declaring a window dead. KDE/Wayland windows can vanish for ~250ms
    # during compositor transitions.
    local grace_period_ms=400
    local grace_poll_ms=100

    debug_function_enter "$function_name" "$@"

    debug_log "$function_name" "Monitoring UUID '$candidate_uuid' for stability (threshold: $stability_threshold checks, max: ${max_wait_ms}ms, min_monitor: ${min_monitor_ms}ms)"

    while (( elapsed_ms < max_wait_ms )); do
        # Check if the candidate UUID still exists
        check_result=$(kdotool getwindowclassname "$candidate_uuid" 2>/dev/null) || check_result=""

        if [[ -n "$check_result" ]]; then
            # Window exists — only count toward stability after min_monitor_ms
            if (( elapsed_ms >= min_monitor_ms )); then
                ((stable_count++)) || true
                debug_log "$function_name" "UUID '$candidate_uuid' alive (stable_count: $stable_count/$stability_threshold, elapsed: ${elapsed_ms}ms)"

                if (( stable_count >= stability_threshold )); then
                    debug_log "$function_name" "UUID '$candidate_uuid' is stable after ${elapsed_ms}ms (splash_detected: $splash_detected)"
                    debug_function_exit "$function_name"
                    echo "${candidate_uuid}|${splash_detected}|${splash_duration_ms}"
                    return 0
                fi
            else
                debug_log "$function_name" "UUID '$candidate_uuid' alive but before min_monitor (${elapsed_ms}ms < ${min_monitor_ms}ms)"
            fi
        else
            # Window missing — apply grace period before declaring dead
            local gone_at_ms=$elapsed_ms
            local grace_elapsed=0
            local window_returned="false"

            debug_log "$function_name" "UUID '$candidate_uuid' missing at ${elapsed_ms}ms — grace period (${grace_period_ms}ms)"

            while (( grace_elapsed < grace_period_ms && elapsed_ms < max_wait_ms )); do
                sleep "$(printf '%d.%03d' "$((grace_poll_ms / 1000))" "$((grace_poll_ms % 1000))")"
                ((grace_elapsed += grace_poll_ms)) || true
                ((elapsed_ms += grace_poll_ms)) || true

                check_result=$(kdotool getwindowclassname "$candidate_uuid" 2>/dev/null) || check_result=""
                if [[ -n "$check_result" ]]; then
                    window_returned="true"
                    break
                fi
            done

            if [[ "$window_returned" == "true" ]]; then
                # Flicker — window came back. Reset stability count, continue monitoring.
                stable_count=0
                debug_log "$function_name" "UUID '$candidate_uuid' returned after ${grace_elapsed}ms flicker — continuing"
                # Fall through to sleep at bottom of loop
            else
                # Window truly dead after grace period
                splash_detected="true"
                splash_duration_ms="$gone_at_ms"
                stable_count=0
                debug_log "$function_name" "UUID '$candidate_uuid' confirmed dead after ${gone_at_ms}ms — scanning for replacement"

                # Track dead UUID to prevent re-detection (UUID reuse by compositor)
                if [[ -n "$dead_uuids" ]]; then
                    dead_uuids="${dead_uuids}|${candidate_uuid}"
                else
                    dead_uuids="$candidate_uuid"
                fi

                # Re-sync DB snapshot so process-of-elimination has fresh baseline.
                # Only delete stale windows — do NOT add new ones, otherwise the
                # replacement window gets tracked and process-of-elimination can't
                # detect it as "new".
                refresh_current_windows
                db_get_all_windows

                # Per-UUID verification: protect live windows that may have
                # been truncated out of CURRENT_UUIDS by the kdotool DBus race
                # before letting db_delete_stale_windows operate on the snapshot.
                _verify_stale_candidates

                # Final safety net for catastrophic kdotool failure: if the
                # snapshot is STILL empty after verification despite the DB
                # having tracked windows, every kdotool call has failed and
                # we cannot trust the result — skip cleanup entirely.
                if [[ ${#CURRENT_UUIDS[@]} -eq 0 && ${#DB_UUIDS[@]} -gt 0 ]]; then
                    debug_log "$function_name" "Empty snapshot post-verification with ${#DB_UUIDS[@]} tracked windows — skipping stale cleanup to preserve DB state"
                else
                    db_delete_stale_windows
                fi

                local remaining_ms=$((max_wait_ms - elapsed_ms))
                if (( remaining_ms <= 0 )); then
                    debug_log "$function_name" "No time remaining to find replacement"
                    debug_function_exit "$function_name"
                    echo "|${splash_detected}|${splash_duration_ms}"
                    return 1
                fi

                # Find replacement, excluding dead UUIDs to prevent zombie pickup
                local new_uuid=""
                local scan_start_ms=""
                scan_start_ms=$(date +%s%3N)
                new_uuid=$(get_uuid_by_process_of_elimination_with_retry "" "$remaining_ms" 100 "$dead_uuids") || true
                local scan_elapsed_ms=$(( $(date +%s%3N) - scan_start_ms ))
                ((elapsed_ms += scan_elapsed_ms)) || true

                if [[ -z "$new_uuid" ]]; then
                    debug_log "$function_name" "No replacement window found within remaining ${remaining_ms}ms"
                    debug_function_exit "$function_name"
                    echo "|${splash_detected}|${splash_duration_ms}"
                    return 1
                fi

                debug_log "$function_name" "Replacement UUID found: '$new_uuid' — restarting stability check"
                candidate_uuid="$new_uuid"
                # Continue loop immediately — replacement search already consumed time
                continue
            fi
        fi

        sleep "$(printf '%d.%03d' "$((check_interval_ms / 1000))" "$((check_interval_ms % 1000))")"
        ((elapsed_ms += check_interval_ms)) || true
    done

    # Timeout reached — accept current candidate if it survived this far
    debug_log "$function_name" "Timeout after ${max_wait_ms}ms — accepting '$candidate_uuid' (stable_count: $stable_count, splash_detected: $splash_detected)"
    debug_function_exit "$function_name"
    echo "${candidate_uuid}|${splash_detected}|${splash_duration_ms}"
    return 0
}

refresh_current_windows() {
    local function_name="refresh_current_windows"

    debug_function_enter "$function_name"

    # Atomic KWin-script snapshot — race-free and faster than 1+2N kdotool
    # calls. Falls through to the kdotool path on failure (deps missing,
    # KWin scripting failure, etc.) so the function stays usable in any
    # environment. See lib/window-management/snapshot.sh and
    # docs/flows/window-detection.md edge case #9.
    if snapshot_all_windows; then
        debug_function_exit "$function_name"
        return 0
    fi

    debug_log "$function_name" "Falling back to kdotool query path"

    # Reset all global arrays
    CURRENT_UUIDS=()
    CURRENT_CLASSES=()
    CURRENT_TITLES=()

    # Get all window UUIDs
    local -a uuids=()
    mapfile -t uuids < <(_kdotool_search_safe)

    if [[ ${#uuids[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0
    fi

    # Collect UUID, class, and title per window in a single pass.
    # This ensures the three arrays stay aligned even if a window
    # disappears mid-scan — the failed property gets "N/A" and the
    # arrays never drift out of sync.
    #
    # Each per-UUID query gets up to two 50ms re-polls on empty stdout to
    # defend against the kdotool DBus delivery race (see edge case #9 in
    # docs/flows/window-detection.md). Without these retries, transient
    # empty results would corrupt CURRENT_CLASSES/TITLES with "N/A" entries
    # that later break class-based matching in POE detection.
    local uuid=""
    local class=""
    local title=""
    for uuid in "${uuids[@]}"; do
        class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
        if [[ -z "$class" ]]; then
            sleep 0.05
            class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
            if [[ -z "$class" ]]; then
                sleep 0.05
                class=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || class=""
            fi
        fi
        class="${class:-N/A}"

        title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""
        if [[ -z "$title" ]]; then
            sleep 0.05
            title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""
            if [[ -z "$title" ]]; then
                sleep 0.05
                title=$(kdotool getwindowname "$uuid" 2>/dev/null) || title=""
            fi
        fi
        title="${title:-N/A}"

        CURRENT_UUIDS+=("$uuid")
        CURRENT_CLASSES+=("$class")
        CURRENT_TITLES+=("$title")
    done

    debug_log "$function_name" "Retrieved ${#CURRENT_UUIDS[@]} windows (UUIDs, classes, titles)"
    debug_function_exit "$function_name"
    return 0
}

# Protect live windows from false stale-cleanup deletes when CURRENT_UUIDS is
# missing entries due to the kdotool DBus delivery race (see edge case #9 in
# docs/flows/window-detection.md). For each UUID in DB_UUIDS not present in
# CURRENT_UUIDS, query kdotool directly with a single retry on empty. If a
# class is returned, the window is alive and was simply truncated out of the
# search response — add it back to CURRENT_UUIDS so db_delete_stale_windows
# does not remove it. If both queries return empty, the window is genuinely
# gone and stale cleanup correctly proceeds.
#
# Cost scales with the number of stale candidates (DB UUIDs not in current
# snapshot). In normal operation that is 0-1; bounded even during a mass
# close because genuinely-dead windows return empty quickly and we don't
# add them to CURRENT_UUIDS.
#
# REQUIRES: CURRENT_UUIDS (from refresh_current_windows) and DB_UUIDS (from
# db_get_all_windows or db_get_existing_window_uuids) to be populated.
# MUTATES: CURRENT_UUIDS by appending verified-alive UUIDs.
_verify_stale_candidates() {
    local function_name="_verify_stale_candidates"

    debug_function_enter "$function_name"

    if [[ ${#DB_UUIDS[@]} -eq 0 ]]; then
        debug_log "$function_name" "No DB UUIDs — nothing to verify"
        debug_function_exit "$function_name"
        return 0
    fi

    local -A current_set=()
    local cur=""
    for cur in "${CURRENT_UUIDS[@]}"; do
        current_set["$cur"]=1
    done

    local protected=0
    local db_uuid=""
    local class=""
    for db_uuid in "${DB_UUIDS[@]}"; do
        # Already in current — not a deletion candidate
        [[ -v current_set["$db_uuid"] ]] && continue

        # Candidate for deletion: verify the window is actually gone before
        # letting db_delete_stale_windows remove it from the DB. Two retries
        # to match the policy used elsewhere for kdotool empty-stdout races.
        class=$(kdotool getwindowclassname "$db_uuid" 2>/dev/null) || class=""
        if [[ -z "$class" ]]; then
            sleep 0.05
            class=$(kdotool getwindowclassname "$db_uuid" 2>/dev/null) || class=""
            if [[ -z "$class" ]]; then
                sleep 0.05
                class=$(kdotool getwindowclassname "$db_uuid" 2>/dev/null) || class=""
            fi
        fi

        if [[ -n "$class" ]]; then
            CURRENT_UUIDS+=("$db_uuid")
            ((protected++)) || true
            debug_log "$function_name" "Protected '$db_uuid' (class='$class') from stale cleanup"
        fi
    done

    if (( protected > 0 )); then
        debug_log "$function_name" "Protected $protected window(s) from false stale cleanup"
    fi
    debug_function_exit "$function_name"
    return 0
}

get_uuid_by_process_of_elimination() {
    local class="$1"  # Optional class parameter for validation
    local is_retry="${2:-FALSE}"
    local uuid=""
    local new_uuid=""
    local found_count=0
    local function_name="get_uuid_by_process_of_elimination"

    debug_function_enter "$function_name" "$@"

    # Get all current window UUIDs from kdotool (populates CURRENT_UUIDS)
    get_existing_windows_uuid
    
    # Get all UUIDs from database (populates DB_UUIDS)
    db_get_existing_window_uuids
    
    debug_log "$function_name" "Current windows: ${#CURRENT_UUIDS[@]}, Database windows: ${#DB_UUIDS[@]}"
    
    # Build lookup table of database UUIDs
    local -A db_lookup
    for uuid in "${DB_UUIDS[@]}"; do
        db_lookup["$uuid"]=1
    done
    
    # Find UUIDs that exist in current windows but not in database
    for uuid in "${CURRENT_UUIDS[@]}"; do
        if [[ ! -v db_lookup[$uuid] ]]; then
            # Skip UUIDs that were previously rejected during retry attempts
            if [[ ${#EXCLUDED_UUIDS[@]} -gt 0 && -v EXCLUDED_UUIDS[$uuid] ]]; then
                debug_log "$function_name" "Skipping excluded UUID: $uuid"
                continue
            fi
            # Reject transient/system windows (notifications, tooltips, etc.)
            if is_transient_window "$uuid"; then
                EXCLUDED_UUIDS["$uuid"]=1
                debug_log "$function_name" "Excluding transient window UUID: $uuid"
                continue
            fi
            new_uuid="$uuid"
            ((found_count++))
            debug_log "$function_name" "Found new UUID: $uuid"
        fi
    done
    
    if [[ $found_count -eq 0 ]]; then
        if [[ "$is_retry" == "FALSE" ]]; then
            debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "No new windows found"
            debug_function_exit "$function_name"
            return 0
        fi
        debug_function_exit "$function_name"
        return 1
    elif [[ $found_count -gt 1 ]]; then
        debug_error "$function_name" "$ERR_MULTIPLE_WINDOWS_FOUND" "Found $found_count new windows, expected 1"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate class if provided
    if [[ -n "$class" ]]; then
        local found_class=""
        found_class=$(get_window_class "$new_uuid")
        
        if [[ "$class" != "$found_class" ]]; then
            debug_error "$function_name" "$ERR_WINDOW_CLASS_MISMATCH" "Expected class '$class', found '$found_class' for UUID '$new_uuid'"
            echo "REJECTED:$new_uuid"
            debug_function_exit "$function_name"
            return 1
        fi
        
        debug_log "$function_name" "Class validation passed: '$class' matches for UUID '$new_uuid'"
    fi
    
    debug_log "$function_name" "New window UUID: $new_uuid"
    debug_function_exit "$function_name"
    echo "$new_uuid"
}

get_uuid_by_process_of_elimination_with_retry() {
    local class="$1"
    local max_wait_ms="${2:-5000}"       # Default 5000ms
    local retry_interval_ms="${3:-100}"  # Default 100ms
    local initial_exclusions="${4:-}"    # Pipe-delimited UUIDs to pre-exclude
    local function_name="get_uuid_by_process_of_elimination_with_retry"
    local uuid=""
    local elapsed_ms=0
    local attempt=0
    local result=""
    local rejected_uuid=""

    debug_function_enter "$function_name" "$@"

    # Initialize/reset global exclusion array for this detection cycle
    EXCLUDED_UUIDS=()

    # Apply initial exclusions (e.g., dead UUIDs from wait_for_stable_window)
    if [[ -n "$initial_exclusions" ]]; then
        local -a excl_array
        IFS='|' read -ra excl_array <<< "$initial_exclusions"
        local excl_uuid
        for excl_uuid in "${excl_array[@]}"; do
            EXCLUDED_UUIDS["$excl_uuid"]=1
            debug_log "$function_name" "Pre-excluding UUID: $excl_uuid"
        done
    fi
    
    debug_log "$function_name" "Waiting up to ${max_wait_ms}ms for window (class: '$class')"
    
    while (( elapsed_ms < max_wait_ms )); do
        ((attempt++))
        rejected_uuid=""
        
        # Attempt to get UUID (class validation happens inside this function)
        result=$(get_uuid_by_process_of_elimination "$class" "TRUE") || true

        if [[ "$result" == REJECTED:* ]]; then
            # Window found but failed validation — exclude from future attempts
            rejected_uuid="${result#REJECTED:}"
            EXCLUDED_UUIDS["$rejected_uuid"]=1
            debug_log "$function_name" "Excluding rejected UUID '$rejected_uuid' from future attempts"
        elif [[ -n "$result" ]]; then
            uuid="$result"
            debug_log "$function_name" "✓ Found UUID '$uuid' after ${elapsed_ms}ms (attempt #$attempt)"
            unset EXCLUDED_UUIDS
            debug_function_exit "$function_name"
            echo "$uuid"
            return 0
        fi
        
        # Wait before next attempt (convert ms to fractional seconds for sleep)
        sleep "$(printf '0.%03d' "$retry_interval_ms")"
        ((elapsed_ms += retry_interval_ms)) || true
        
        debug_log "$function_name" "Attempt #$attempt: No UUID yet (elapsed: ${elapsed_ms}ms)"
    done
    
    # Timeout reached — cleanup and report
    EXCLUDED_UUIDS=()
    debug_log "$function_name" "Timeout after ${max_wait_ms}ms waiting for window (class: '$class')"
    debug_function_exit "$function_name"
    return 1
}

get_existing_windows_uuid() {
    local function_name="get_existing_windows_uuid"

    debug_function_enter "$function_name"

    CURRENT_UUIDS=()

    mapfile -t CURRENT_UUIDS < <(_kdotool_search_safe)

    if [[ ${#CURRENT_UUIDS[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0  # Not an error - just no windows open
    fi

    debug_log "$function_name" "Retrieved ${#CURRENT_UUIDS[@]} uuids"
    debug_function_exit "$function_name"
    return 0
}

get_uuid() {
    local class="$1"
    local window_title="$2"
    local -a matching_uuids=()
    local uuid=""
    local function_name="get_uuid"

    debug_function_enter "$function_name" "$@"

    # Need at least one search criterion
    if [[ -z "$class" && -z "$window_title" ]]; then
        debug_error "$function_name" "$ERR_INVALID_ARGUMENT" "Must provide at least class or window_title"
        debug_function_exit "$function_name"
        return 1
    fi

    # Step 1: Search by class if provided
    if [[ -n "$class" ]]; then
        local safe_class=""
        safe_class=$(safe_kdotool_pattern "$class")

        debug_log "$function_name" "Searching for windows with class: '$class' (escaped: '$safe_class')"
        mapfile -t matching_uuids < <(_kdotool_search_safe --class "$safe_class")

        if [[ ${#matching_uuids[@]} -eq 0 ]]; then
            debug_log "$function_name" "No windows found with class '$class'"
            debug_function_exit "$function_name"
            return 0
        fi

        debug_log "$function_name" "Found ${#matching_uuids[@]} window(s) with class '$class'"
    else
        # No class filter - get all windows
        debug_log "$function_name" "No class filter, searching all windows"
        mapfile -t matching_uuids < <(_kdotool_search_safe)
    fi

    # Step 2: Filter by window title if needed to disambiguate
    if [[ -n "$window_title" && ${#matching_uuids[@]} -gt 1 ]]; then
        debug_log "$function_name" "Multiple matches (${#matching_uuids[@]}), filtering by title: '$window_title'"
        
        local -a title_matches=()
        local current_title=""
        
        for uuid in "${matching_uuids[@]}"; do
            current_title=$(kdotool getwindowname "$uuid")
            if [[ "$current_title" == *"$window_title"* ]]; then
                title_matches+=("$uuid")
                debug_log "$function_name" "Title match: UUID '$uuid' has title '$current_title'"
            fi
        done
        
        if [[ ${#title_matches[@]} -gt 0 ]]; then
            matching_uuids=("${title_matches[@]}")
            debug_log "$function_name" "Narrowed to ${#matching_uuids[@]} window(s) by title"
        else
            debug_log "$function_name" "No title matches, keeping all ${#matching_uuids[@]} class matches"
        fi
    fi

    # Step 3: Return result based on match count
    if [[ ${#matching_uuids[@]} -eq 0 ]]; then
        debug_log "$function_name" "No windows found"
        debug_function_exit "$function_name"
        return 0
    elif [[ ${#matching_uuids[@]} -eq 1 ]]; then
        uuid="${matching_uuids[0]}"
        debug_log "$function_name" "Found exactly one UUID: '$uuid'"
        debug_function_exit "$function_name"
        echo "$uuid"
        return 0
    else
        debug_error "$function_name" "$ERR_MULTIPLE_WINDOWS_FOUND" "Found ${#matching_uuids[@]} windows"
        debug_function_exit "$function_name"
        return 1
    fi
}

get_window_class() {
    local uuid="$1" 
    local class=""
    local function_name="get_window_class"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get window class
    class=$(kdotool getwindowclassname "$uuid")

    if [[ -z "$class" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_CLASS_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$class'"

    debug_function_exit "$function_name"
    echo "$class"
}

get_window_title() {
    local uuid="$1" 
    local window_title=""
    local function_name="get_window_title"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get window title
    window_title=$(kdotool getwindowname "$uuid")

    if [[ -z "$window_title" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_TITLE_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$window_title'"

    debug_function_exit "$function_name"
    echo "$window_title"
}

get_window_pid() {
    local uuid="$1" 
    local pid=""
    local function_name="get_window_pid"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get window pid
    pid=$(kdotool getwindowpid "$uuid")

    if [[ -z "$pid" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_PID_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$pid'"

    debug_function_exit "$function_name"
    echo "$pid"
}

get_process_name() {
    local pid="$1"
    local process_name=""
    local function_name="get_process_name"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$pid" "pid" || return 1
    
    # Get process name using ps
    process_name=$(ps -p "$pid" -o comm= 2>/dev/null)
    
    if [[ -z "$process_name" ]]; then
        debug_error "$function_name" "Process name not found for PID: $pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "PID '$pid' → '$process_name'"
    
    debug_function_exit "$function_name"
    echo "$process_name"
    return 0
}

get_executable_path() {
    local pid="$1"
    local executable_path=""
    local function_name="get_executable_path"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$pid" "pid" || return 1
    
    # Get executable path from /proc
    executable_path=$(readlink -f /proc/"$pid"/exe 2>/dev/null)
    
    if [[ -z "$executable_path" ]]; then
        debug_error "$function_name" "Executable path not found for PID: $pid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "PID '$pid' → '$executable_path'"
    
    debug_function_exit "$function_name"
    echo "$executable_path"
    return 0
}

get_window_size() {
    local uuid="$1" 
    local window_size=""
    local function_name="get_window_size"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get window size
    window_size=$(kdotool getwindowgeometry "$uuid" | grep "Geometry:" | awk '{print $2}')

    if [[ -z "$window_size" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_SIZE_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "'$uuid' → '$window_size'"

    debug_function_exit "$function_name"
    echo "$window_size"
}

get_window_position() {
    local uuid="$1" 
    local window_position=""
    local function_name="get_window_position"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Get window position
    window_position=$(kdotool getwindowgeometry "$uuid" | grep "Position:" | awk '{print $2}')
    
    if [[ -z "$window_position" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_POSITION_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    debug_log "$function_name" "'$uuid' → '$window_position'"

    debug_function_exit "$function_name"
    echo "$window_position"
}

get_active_window_uuid() {
    local uuid=""
    local function_name="get_active_window_uuid"

    debug_function_enter "$function_name"

    # Get the currently focused window UUID
    uuid=$(_kdotool_getactivewindow_safe)

    if [[ -z "$uuid" ]]; then
        debug_log "$function_name" "No active window (desktop may be focused)"
        debug_function_exit "$function_name"
        return 0
    fi

    debug_log "$function_name" "Active window: '$uuid'"
    debug_function_exit "$function_name"
    echo "$uuid"
}

window_exists() {
    local uuid="$1"
    local function_name="window_exists"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Check if UUID exists in CURRENT_UUIDS global array
    for current_uuid in "${CURRENT_UUIDS[@]}"; do
        if [[ "$current_uuid" == "$uuid" ]]; then
            debug_log "$function_name" "Window '$uuid' exists"
            debug_function_exit "$function_name"
            return 0
        fi
    done

    debug_log "$function_name" "Window '$uuid' does not exist"
    debug_function_exit "$function_name"
    return 1
}

window_not_exists() {
    local uuid="$1"
    local result=""

    result=$(kdotool getwindowclassname "$uuid" 2>/dev/null) || result=""

    if [[ -z "$result" ]]; then
        return 0  # no output → window is gone
    fi

    return 1  # got output → window still exists
}

activate_window() {
    local uuid="$1"
    local function_name="activate_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Skip if window is already active (windowactivate toggles, which would minimize it)
    local active_uuid=""
    active_uuid=$(get_active_window_uuid)

    if [[ "$active_uuid" == "$uuid" ]]; then
        debug_log "$function_name" "'$uuid' is already active, skipping"
        debug_function_exit "$function_name"
        return
    fi

    # Activate window
    kdotool windowactivate "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' activated."
    debug_function_exit "$function_name"
}

raise_window() {
    local uuid="$1"
    local function_name="raise_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Raise window
    kdotool windowraise "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' raised."
    debug_function_exit "$function_name"
}

move_window() {
    local uuid="$1"
    local x="$2"
    local y="$3"
    local function_name="move_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Move window
    kdotool windowmove "$uuid" "$x" "$y"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' moved to x=$x y=$y."
    debug_function_exit "$function_name"
}

size_window() {
    local uuid="$1"
    local width="$2"
    local height="$3"
    local function_name="size_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Size window
    kdotool windowsize "$uuid" "$width" "$height"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' sized to width=$width height=$height."
    debug_function_exit "$function_name"
}

minimize_window() {
    local uuid="$1"
    local function_name="minimize_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    #Minimize window
    kdotool windowminimize "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' minimized."
    debug_function_exit "$function_name"
}

close_window() {
    local uuid="$1"
    local function_name="close_window"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1

    # Close window
    kdotool windowclose "$uuid"
    sleep "$WINDOW_DELAY"

    debug_log "$function_name" "'$uuid' closed."
    debug_function_exit "$function_name"
}
