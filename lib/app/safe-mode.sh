#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_APP_SAFE_MODE_LOADED" || return 0

# Source required modules
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../utils/display.sh
source "${LIB_DIR}/utils/display.sh"
# shellcheck source=../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"

safe_mode_launch_and_detect() {
    local app_id="$1"
    local function_name="safe_mode_launch_and_detect"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    # Get display name
    local display_name
    display_name=$(db_get_display_name "$app_id")
    
    # Brief notice replaces the old multi-step preparation
    echo "" >&3
    echo "ℹ️  Starting safe mode for $display_name..." >&3
    echo "" >&3
    
    # Launch and measure time — also detects UUID
    local new_uuid
    new_uuid=$(safe_mode_measure_launch_time "$app_id")
    
    # Check if measurement succeeded
    if [[ -z "$new_uuid" ]]; then
        echo "" >&3
        echo "Options:" >&3
        echo "  [R] Retry launch" >&3
        echo "  [S] Skip this application" >&3
        echo "" >&3
        read -r -p "Choice: " recovery
        recovery=$(echo "$recovery" | tr '[:upper:]' '[:lower:]')
        
        case "$recovery" in
            r)
                debug_log "$function_name" "Retrying..."
                safe_mode_launch_and_detect "$app_id"
                return $?
                ;;
            s)
                debug_log "$function_name" "Skipping - marking as completed"
                db_set_safe_mode_completed "$app_id"
                debug_function_exit "$function_name" "Skipped"
                return 0
                ;;
            *)
                debug_function_exit "$function_name" "Aborted"
                return 1
                ;;
        esac
    fi
    
    debug_log "$function_name" "Detected UUID via launch time measurement: $new_uuid"
    
    # --- Auto-gather all metadata silently ---
    
    # 1. Get class from detected window
    local detected_class
    detected_class=$(get_window_class "$new_uuid")
    
    # 2. Get launch time (already stored by safe_mode_measure_launch_time)
    local launch_time_ms
    launch_time_ms=$(db_get_launch_time "$app_id")
    
    # 3. Auto-detect PID validation data
    local pid_data
    pid_data=$(safe_mode_auto_detect_pid "$app_id" "$new_uuid")
    local pid_supported pid_process_name pid_exe_path
    IFS='|' read -r pid_supported pid_process_name pid_exe_path <<< "$pid_data"
    
    # 4. Auto-detect title pattern
    local title_pattern
    title_pattern=$(safe_mode_auto_detect_title_pattern "$app_id" "$new_uuid" "$display_name" "$detected_class")
    
    # 5. Auto-detect launch mode (may launch/close a second instance)
    local launch_mode_result
    launch_mode_result=$(safe_mode_auto_detect_launch_mode "$app_id" "$new_uuid" "$detected_class")
    
    local launch_mode pid_override
    IFS='|' read -r launch_mode pid_override <<< "$launch_mode_result"
    
    # Override PID data if multi-instance app shares PIDs (e.g., Electron apps)
    if [[ "$pid_override" == "shared" ]]; then
        pid_supported="false"
        pid_process_name=""
        pid_exe_path=""
    fi
    
    # --- Show combined summary and get single confirmation ---
    local confirm_result
    confirm_result=$(safe_mode_display_summary_and_confirm "$display_name" "$detected_class" \
        "$launch_time_ms" "$pid_supported" "$pid_process_name" \
        "$title_pattern" "$launch_mode")
    
    # Handle confirmation result
    case "$confirm_result" in
        accept|title_edit)
            # Accept or Title pattern edit
            if [[ "$confirm_result" == "title_edit" ]]; then
                local window_title
                window_title=$(get_window_title "$new_uuid")
                title_pattern=$(safe_mode_manual_title_pattern_selection "$new_uuid" "$window_title")
            fi
            
            # Store all metadata
            safe_mode_store_metadata "$app_id" "$new_uuid"
            
            if [[ "$pid_supported" == "true" ]]; then
                db_set_pid_validation_data "$app_id" "true" "$pid_process_name" "$pid_exe_path"
            else
                db_set_pid_validation_data "$app_id" "false" "" ""
            fi
            
            if [[ -n "$title_pattern" ]]; then
                db_set_window_title_pattern "$app_id" "$title_pattern"
            fi
            
            db_set_launch_mode "$app_id" "$launch_mode"
            
            # Close window and mark complete
            close_window "$new_uuid"
            db_set_safe_mode_completed "$app_id"
            
            echo "" >&3
            echo "✅ Safe mode complete for $display_name" >&3
            echo "" >&3
            
            debug_function_exit "$function_name" "Success"
            echo "$new_uuid"
            return 0
            ;;
        skip)
            # Skip — mark as completed without storing metadata
            close_window "$new_uuid"
            db_set_safe_mode_completed "$app_id"
            
            echo "" >&3
            echo "⏭️  Skipped safe mode for $display_name" >&3
            echo "" >&3
            
            debug_function_exit "$function_name" "Skipped"
            return 0
            ;;
        retry)
            # Retry — close window and start over
            close_window "$new_uuid"
            
            debug_log "$function_name" "Retrying..."
            safe_mode_launch_and_detect "$app_id"
            return $?
            ;;
    esac
}

detect_safe_mode_apps() {
    local workspace_name="$1"
    local script_path="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}.sh"
    local function_name="detect_safe_mode_apps"
    local -a safe_mode_apps=()
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_file_exists "$script_path" || return 1
    
    # Parse workspace script to find all launch_by_app_id calls
    while IFS= read -r line; do
        if [[ "$line" =~ launch_by_app_id[[:space:]]+\"[^\"]+\"[[:space:]]+\"[^\"]+\"[[:space:]]+\"([^\"]+)\" ]]; then
            local app_id="${BASH_REMATCH[1]}"
            
            # Check if app has custom file
            local has_custom_file=false
            if [[ -f "$LIB_DIR/launchers/${app_id}.sh" ]]; then
                has_custom_file=true
            fi
            
            # Check if safe mode completed
            local safe_mode_done
            safe_mode_done=$(db_get_safe_mode_completed "$app_id")
            
            # If desktop launch, no custom file, and not validated → needs safe mode
            if [[ "$has_custom_file" == "false" ]] && \
               [[ "$safe_mode_done" != "1" ]]; then
                safe_mode_apps+=("$app_id")

                db_set_requires_safe_mode "$app_id" "TRUE"

                debug_log "$function_name" "App needs safe mode: $app_id"
            fi
        fi
    done < "$script_path"
    
    debug_function_exit "$function_name"
    
    # Return array as newline-separated list
    printf '%s\n' "${safe_mode_apps[@]}"
}

prompt_safe_mode() {
    local -a apps=("$@")
    local function_name="prompt_safe_mode"

    debug_function_enter "$function_name" "App count: ${#apps[@]}"

    while true; do
        # If all apps were removed via disable sub-menu, proceed to open
        if [[ ${#apps[@]} -eq 0 ]]; then
            debug_function_exit "$function_name" "All apps disabled"
            echo "open"
            return 0
        fi

        echo "" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "⚠️  SAFE MODE RECOMMENDED" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3
        echo "The following applications have not been validated:" >&3
        echo "" >&3

        for app_id in "${apps[@]}"; do
            local display_name
            display_name=$(db_get_display_name "$app_id")
            echo "  • $display_name ($app_id)" >&3
        done

        echo "" >&3
        echo "Safe mode is a one-time process that ensures reliable window detection." >&3
        echo "" >&3
        echo "Options:" >&3
        echo "  [A] Accept — run safe mode now, then open workspace" >&3
        echo "  [S] Skip — open workspace anyway (will ask again next time)" >&3
        echo "  [D] Disable — turn off safe-mode prompts" >&3
        echo "  [Q] Quit — cancel" >&3
        echo "" >&3

        local choice
        read -r -p "Choice: " choice
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

        case "$choice" in
            a)
                debug_function_exit "$function_name" "Accept"
                echo "accept"
                return 0
                ;;
            s)
                debug_function_exit "$function_name" "Skip"
                echo "skip"
                return 0
                ;;
            d)
                # Enter disable sub-menu
                local disable_result
                disable_result=$(prompt_safe_mode_disable_menu apps)
                case "$disable_result" in
                    open)
                        debug_function_exit "$function_name" "Disabled — proceeding to open"
                        echo "open"
                        return 0
                        ;;
                    back)
                        # Continue main loop (apps array may have been modified)
                        continue
                        ;;
                esac
                ;;
            q)
                debug_function_exit "$function_name" "Quit"
                echo "quit"
                return 0
                ;;
            *)
                echo "Invalid choice. Please select A, S, D, or Q." >&3
                continue
                ;;
        esac
    done
}

prompt_safe_mode_disable_menu() {
    local -n apps_ref="$1"
    local function_name="prompt_safe_mode_disable_menu"

    debug_function_enter "$function_name"

    echo "" >&3
    echo "Disable safe-mode prompting:" >&3
    echo "" >&3
    echo "  [D] Disable safe-mode prompting globally" >&3

    local i=1
    for app_id in "${apps_ref[@]}"; do
        local display_name
        display_name=$(db_get_display_name "$app_id")
        echo "  [$i] $display_name ($app_id) — skip this app only" >&3
        ((i++))
    done

    echo "  [A] All listed apps — skip all apps shown above" >&3
    echo "  [B] Back" >&3
    echo "" >&3

    local choice
    read -r -p "Choice: " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice" in
        d)
            # Disable globally via config file
            safe_mode_disable_globally
            debug_function_exit "$function_name" "Disabled globally"
            echo "open"
            return 0
            ;;
        a)
            # Mark all listed apps as completed
            for app_id in "${apps_ref[@]}"; do
                db_set_safe_mode_completed "$app_id"
            done
            apps_ref=()
            echo "" >&3
            echo "✓ Safe mode skipped for all listed apps." >&3
            debug_function_exit "$function_name" "All apps skipped"
            echo "open"
            return 0
            ;;
        b)
            debug_function_exit "$function_name" "Back"
            echo "back"
            return 0
            ;;
        *)
            # Check if it's a number selecting a specific app
            if [[ "$choice" =~ ^[0-9]+$ ]] && \
               [[ "$choice" -ge 1 ]] && \
               [[ "$choice" -le "${#apps_ref[@]}" ]]; then
                local idx=$((choice - 1))
                local selected_app="${apps_ref[$idx]}"
                local selected_name
                selected_name=$(db_get_display_name "$selected_app")

                db_set_safe_mode_completed "$selected_app"

                # Remove from array
                apps_ref=("${apps_ref[@]:0:$idx}" "${apps_ref[@]:$((idx + 1))}")

                echo "" >&3
                echo "✓ Safe mode skipped for $selected_name." >&3

                if [[ ${#apps_ref[@]} -eq 0 ]]; then
                    debug_function_exit "$function_name" "All apps removed"
                    echo "open"
                    return 0
                fi

                debug_function_exit "$function_name" "App removed, returning to main"
                echo "back"
                return 0
            fi

            echo "Invalid choice." >&3
            debug_function_exit "$function_name" "Invalid choice"
            echo "back"
            return 0
            ;;
    esac
}

safe_mode_disable_globally() {
    local function_name="safe_mode_disable_globally"
    local config_file="$KDOITALL_CONFIG"
    local config_dir
    config_dir=$(dirname "$config_file")

    debug_function_enter "$function_name"

    # Ensure config directory exists
    mkdir -p "$config_dir"

    if [[ -f "$config_file" ]]; then
        # Check if SAFE_MODE_PROMPTING line exists (commented or uncommented)
        if grep -q '^#\s*SAFE_MODE_PROMPTING=' "$config_file"; then
            # Replace commented line with active disabled setting
            sed -i 's/^#\s*SAFE_MODE_PROMPTING=.*/SAFE_MODE_PROMPTING="disabled"/' "$config_file"
        elif grep -q '^SAFE_MODE_PROMPTING=' "$config_file"; then
            # Replace existing uncommented line
            sed -i 's/^SAFE_MODE_PROMPTING=.*/SAFE_MODE_PROMPTING="disabled"/' "$config_file"
        else
            # Append setting
            echo '' >> "$config_file"
            echo 'SAFE_MODE_PROMPTING="disabled"' >> "$config_file"
        fi
    else
        # Create config file with the setting
        cat > "$config_file" << 'CONFIGEOF'
#!/bin/bash

# kdoitall user configuration
SAFE_MODE_PROMPTING="disabled"
CONFIGEOF
    fi

    # Re-source and verify
    # shellcheck source=/dev/null
    source "$config_file"

    if [[ "${SAFE_MODE_PROMPTING:-}" == "disabled" ]]; then
        echo "" >&3
        echo "✓ Safe-mode prompting disabled in $config_file" >&3
        echo "  Re-enable by changing SAFE_MODE_PROMPTING to \"enabled\" in that file." >&3
    else
        echo "" >&3
        echo "⚠️  Failed to update config file automatically." >&3
        echo "  Manually edit $config_file and set:" >&3
        echo "    SAFE_MODE_PROMPTING=\"disabled\"" >&3
    fi

    debug_function_exit "$function_name"
    return 0
}

safe_mode_measure_launch_time() {
    local app_id="$1"
    local function_name="safe_mode_measure_launch_time"
    local start_time=""
    local end_time=""
    local elapsed_ms=0
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get display name
    local display_name=""
    display_name=$(db_get_display_name "$app_id")
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "⏱️  LAUNCH TIME MEASUREMENT" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Application: $display_name ($app_id)" >&3
    echo "Measuring launch time with generous timeout (30 seconds)..." >&3
    echo "" >&3
    
    # Refresh database before launch
    echo "Scanning existing windows..." >&3
    auto_detect_windows

    # Record start time (milliseconds since epoch)
    start_time=$(date +%s%3N)
    
    # Launch application
    echo "Launching $display_name..." >&3
    (gtk-launch "$app_id" &>/dev/null &)
    
    # Wait for window with extended timeout using retry function
    echo "Waiting for window to appear (timeout: 30 seconds)..." >&3
    echo "" >&3
    
    # Use get_uuid_by_process_of_elimination_with_retry with 30 second timeout
    local uuid=""
    uuid=$(get_uuid_by_process_of_elimination_with_retry "" 30 0.1)
    
    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_NOT_FOUND" "Launch time measurement failed - no window detected"
        echo "" >&3
        echo "❌ Could not measure launch time - window not detected within 30 seconds" >&2
        echo "" >&2
        echo "This usually means:" >&2
        echo "  • Application failed to launch" >&2
        echo "  • Application takes longer than 30 seconds to start" >&2
        echo "  • Application is already running (single-instance)" >&2
        echo "" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Record end time
    end_time=$(date +%s%3N)
    
    # Calculate elapsed time in milliseconds
    elapsed_ms=$((end_time - start_time))

    # Minimize window (keep it alive for further metadata gathering)
    minimize_window "$uuid"
    
    echo "" >&3
    echo "✓ Window detected after ${elapsed_ms}ms" >&3
    echo "" >&3
    # Store measurement in database
    db_set_launch_time "$app_id" "$elapsed_ms"
    
    debug_log "$function_name" "Launch time measured: ${elapsed_ms}ms"
    debug_function_exit "$function_name"

    echo "$uuid"
    return 0
}

safe_mode_auto_detect_pid() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_auto_detect_pid"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    # Get PID from window
    local pid
    pid=$(get_window_pid "$uuid" 2>/dev/null)
    
    if [[ -z "$pid" ]]; then
        debug_log "$function_name" "PID not available for $app_id"
        debug_function_exit "$function_name"
        echo "false||"
        return 0
    fi
    
    # Get process information
    local process_name=""
    local executable_path=""
    
    process_name=$(get_process_name "$pid" 2>/dev/null)
    executable_path=$(get_executable_path "$pid" 2>/dev/null)
    
    if [[ -z "$process_name" ]]; then
        debug_log "$function_name" "Could not resolve process name for PID $pid"
        debug_function_exit "$function_name"
        echo "false||"
        return 0
    fi
    
    debug_log "$function_name" "PID validation data: supports=true, process='$process_name', path='$executable_path'"
    debug_function_exit "$function_name"
    
    # Return pipe-separated: supported|process_name|executable_path
    echo "true|${process_name}|${executable_path}"
    return 0
}

safe_mode_auto_detect_title_pattern() {
    local app_id="$1"
    local uuid="$2"
    local display_name="$3"
    local class="$4"
    local function_name="safe_mode_auto_detect_title_pattern"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    # Get current window title
    local current_title
    current_title=$(get_window_title "$uuid")
    
    if [[ -z "$current_title" ]]; then
        debug_log "$function_name" "No window title available"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Parse title to get suggestions (rightmost first)
    local -a suggestions=()
    mapfile -t suggestions < <(parse_window_title_segments "$current_title")
    
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        debug_log "$function_name" "No separators found in title, no pattern to auto-select"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Auto-select: prefer a suggestion containing display_name or class
    local selected_pattern=""
    local display_name_lower
    local class_lower
    display_name_lower=$(echo "$display_name" | tr '[:upper:]' '[:lower:]')
    class_lower=$(echo "$class" | tr '[:upper:]' '[:lower:]')
    
    for suggestion in "${suggestions[@]}"; do
        local suggestion_lower
        suggestion_lower=$(echo "$suggestion" | tr '[:upper:]' '[:lower:]')
        
        if [[ -n "$display_name" && "$suggestion_lower" == *"$display_name_lower"* ]]; then
            selected_pattern="$suggestion"
            debug_log "$function_name" "Auto-selected pattern matching display name: '$suggestion'"
            break
        fi
        
        if [[ -n "$class" && "$suggestion_lower" == *"$class_lower"* ]]; then
            selected_pattern="$suggestion"
            debug_log "$function_name" "Auto-selected pattern matching class: '$suggestion'"
            break
        fi
    done
    
    # Fallback: use the rightmost suggestion (first in array)
    if [[ -z "$selected_pattern" ]]; then
        selected_pattern="${suggestions[0]}"
        debug_log "$function_name" "No name/class match, using rightmost pattern: '$selected_pattern'"
    fi
    
    debug_function_exit "$function_name"
    echo "$selected_pattern"
    return 0
}

safe_mode_manual_title_pattern_selection() {
    local uuid="$1"
    local current_title="$2"
    local function_name="safe_mode_manual_title_pattern_selection"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$current_title" "current_title" || return 1
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "📝 MANUAL TITLE PATTERN SELECTION" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Current window title: \"$current_title\"" >&3
    echo "" >&3
    
    # Parse title to get suggestions
    local -a suggestions=()
    mapfile -t suggestions < <(parse_window_title_segments "$current_title")
    
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        echo "No separators found in the window title." >&3
        echo "" >&3
        read -r -p "Enter a custom pattern (or press Enter to skip): " pattern
        
        if [[ -z "$pattern" ]]; then
            debug_function_exit "$function_name" "Skipped"
            return 0
        fi
        
        # Validate custom pattern exists in title
        if [[ ! "$current_title" =~ $pattern ]]; then
            echo "" >&3
            echo "⚠️  Warning: Pattern \"$pattern\" not found in current title!" >&3
            read -r -p "Save anyway? [y/N]: " save_anyway
            save_anyway=$(echo "$save_anyway" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$save_anyway" != "y" ]]; then
                debug_function_exit "$function_name" "Rejected"
                return 0
            fi
        fi
        
        echo "" >&3
        echo "✓ Title pattern selected: \"$pattern\"" >&3
        
        debug_function_exit "$function_name"
        echo "$pattern"
        return 0
    fi
    
    # We have suggestions - display them
    echo "Suggestions (starting with rightmost):" >&3
    echo "" >&3
    
    local i=1
    for suggestion in "${suggestions[@]}"; do
        echo "  [$i] \"$suggestion\"" >&3
        ((i++))
    done
    
    echo "  [$i] Custom pattern (enter your own)" >&3
    local custom_option=$i
    echo "  [0] No pattern (skip)" >&3
    echo "" >&3
    
    # Get user choice
    local choice
    read -r -p "Select a pattern (0-$i): " choice
    
    # Skip
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        echo "Skipping title pattern." >&3
        debug_function_exit "$function_name" "Skipped"
        return 0
    fi
    
    # Validate choice is a number
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Invalid choice. Skipping title pattern." >&3
        debug_function_exit "$function_name" "Invalid input"
        return 0
    fi
    
    local pattern=""
    
    # Check if custom option was selected
    if [[ "$choice" -eq "$custom_option" ]]; then
        echo "" >&3
        read -r -p "Enter custom pattern: " pattern
        
        if [[ -z "$pattern" ]]; then
            echo "No pattern entered. Skipping." >&3
            debug_function_exit "$function_name" "No custom pattern entered"
            return 0
        fi
        
        # Validate custom pattern exists in title
        if [[ ! "$current_title" =~ $pattern ]]; then
            echo "" >&3
            echo "⚠️  Warning: Pattern \"$pattern\" not found in current title!" >&3
            read -r -p "Save anyway? [y/N]: " save_anyway
            save_anyway=$(echo "$save_anyway" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$save_anyway" != "y" ]]; then
                echo "Pattern not saved." >&3
                debug_function_exit "$function_name" "Custom pattern rejected"
                return 0
            fi
        fi
    else
        # User selected a suggestion
        local suggestion_index=$((choice - 1))
        
        # Validate index is in range
        if [[ "$suggestion_index" -lt 0 || "$suggestion_index" -ge "${#suggestions[@]}" ]]; then
            echo "Invalid choice. Skipping title pattern." >&3
            debug_function_exit "$function_name" "Choice out of range"
            return 0
        fi
        
        pattern="${suggestions[$suggestion_index]}"
    fi
    
    echo "" >&3
    echo "✓ Title pattern selected: \"$pattern\"" >&3
    
    debug_log "$function_name" "Title pattern selected: $pattern"
    debug_function_exit "$function_name"
    echo "$pattern"
    return 0
}

safe_mode_auto_detect_launch_mode() {
    local app_id="$1"
    local existing_uuid="$2"
    local class="$3"
    local function_name="safe_mode_auto_detect_launch_mode"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$existing_uuid" "existing_uuid" || return 1
    
    echo "Testing multi-instance support..." >&3
    
    # Refresh database before second launch
    auto_detect_windows
    
    # Launch second instance
    (gtk-launch "$app_id" &>/dev/null &)
    
    # Wait up to 10 seconds for a new window
    local new_uuid=""
    new_uuid=$(get_uuid_by_process_of_elimination_with_retry "$class" 10 0.1)
    
    local detected_mode=""
    local pid_override=""
    
    if [[ -n "$new_uuid" ]]; then
        detected_mode="$LAUNCH_MODE_MULTI"
        debug_log "$function_name" "Second window detected: $new_uuid → multi mode"
        
        # PID cross-check: do both windows share the same PID?
        # Electron-based apps (VS Code, Chrome, etc.) share a single PID across all windows,
        # which makes PID-based validation unreliable for distinguishing between them.
        local first_pid second_pid
        first_pid=$(get_window_pid "$existing_uuid" 2>/dev/null)
        second_pid=$(get_window_pid "$new_uuid" 2>/dev/null)
        
        if [[ -n "$first_pid" && -n "$second_pid" && "$first_pid" == "$second_pid" ]]; then
            pid_override="shared"
            debug_log "$function_name" "Both windows share PID $first_pid → PID validation unreliable"
        elif [[ -n "$first_pid" && -n "$second_pid" ]]; then
            debug_log "$function_name" "Different PIDs ($first_pid vs $second_pid) → PID validation reliable"
        fi
        
        # Close second window
        close_window "$new_uuid"
    else
        # No second window appeared — could be single or unique
        detected_mode="$LAUNCH_MODE_SINGLE_OR_UNIQUE"
        debug_log "$function_name" "No second window detected → single_or_unique mode"
    fi
    
    echo "✓ Launch mode detected: $detected_mode" >&3
    
    debug_function_exit "$function_name"
    # Return pipe-separated: mode|pid_override
    echo "${detected_mode}|${pid_override}"
    return 0
}

safe_mode_display_summary_and_confirm() {
    local display_name="$1"
    local class="$2"
    local launch_time_ms="$3"
    local pid_supported="$4"
    local pid_process_name="$5"
    local title_pattern="$6"
    local launch_mode="$7"
    local function_name="safe_mode_display_summary_and_confirm"
    
    debug_function_enter "$function_name" "$@"
    
    # Format PID display
    local pid_display="No"
    if [[ "$pid_supported" == "true" ]]; then
        pid_display="Yes ($pid_process_name)"
    fi
    
    # Format title pattern display
    local pattern_display="(none)"
    if [[ -n "$title_pattern" ]]; then
        pattern_display="$title_pattern"
    fi
    
    # Format launch mode display
    local mode_display="multi"
    if [[ "$launch_mode" != "$LAUNCH_MODE_MULTI" ]]; then
        mode_display="not multi"
    fi
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "📊 SAFE MODE RESULTS" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "  Application:   $display_name" >&3
    echo "  Class:         $class" >&3
    echo "  Launch Time:   ${launch_time_ms}ms" >&3
    echo "  PID Supported: $pid_display" >&3
    echo "  Title Pattern: $pattern_display" >&3
    echo "  Launch Mode:   $mode_display" >&3
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    
    local choice
    read -r -p "Accept? [Y]es / [R]etry / [S]kip / [T]itle pattern: " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    
    case "$choice" in
        y|"")
            debug_function_exit "$function_name" "Accepted"
            echo "accept"
            return 0
            ;;
        r)
            debug_function_exit "$function_name" "Retry"
            echo "retry"
            return 0
            ;;
        t)
            debug_function_exit "$function_name" "Title pattern edit"
            echo "title_edit"
            return 0
            ;;
        s)
            debug_function_exit "$function_name" "Skipped"
            echo "skip"
            return 0
            ;;
        *)
            echo "Invalid choice. Accepting results." >&3
            debug_function_exit "$function_name" "Accepted (default)"
            echo "accept"
            return 0
            ;;
    esac
}

safe_mode_store_metadata() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_store_metadata"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    # Extract metadata
    local class
    class=$(get_window_class "$uuid")
    
    # Store class in database using db function
    db_set_app_class "$app_id" "$class"
    
    debug_log "$function_name" "Stored: class=$class"
    
    echo "" >&3
    echo "✓ Metadata stored successfully:" >&3
    echo "  • Class: $class" >&3
    
    debug_function_exit "$function_name"
    return 0
}
