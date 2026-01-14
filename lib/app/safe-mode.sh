#!/bin/bash

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
    display_name=$(db_get_app_display_name "$app_id")
    
    # Use launch time measurement for detection
    local new_uuid
    new_uuid=$(safe_mode_measure_launch_time "$app_id")
    
    # Check if measurement succeeded
    if [[ -z "$new_uuid" ]]; then
        # Launch time measurement failed - offer recovery options
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
    
    # Verify detection with user
    if ! safe_mode_verify_window "$app_id" "$new_uuid"; then
        echo "" >&3
        echo "Options:" >&3
        echo "  [R] Retry launch" >&3
        echo "  [S] Skip this application" >&3
        echo "" >&3
        read -r -p "Choice: " recovery
        recovery=$(echo "$recovery" | tr '[:upper:]' '[:lower:]')
        
        case "$recovery" in
            r)
                # Close the wrong window first
                close_window "$new_uuid"
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
    
    # Store validated data
    safe_mode_store_metadata "$app_id" "$new_uuid"
    
    # Run comprehensive validation to gather additional metadata
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "📊 GATHERING METADATA" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    
    # Test PID-based validation
    safe_mode_test_pid_validation "$app_id" "$new_uuid"
    
    # Analyze window title pattern
    local title
    title=$(get_window_title "$new_uuid")
    safe_mode_analyze_title_pattern "$app_id" "$new_uuid" "$title"
    
    # Test multi-instance support
    safe_mode_test_multi_instance "$app_id" "$new_uuid"

    # Close first window
    echo "Closing first window..." >&3
    close_window "$new_uuid"
    
    echo "" >&3
    echo "✓ Metadata collection complete" >&3
    
    # Mark safe mode as complete
    db_set_safe_mode_completed "$app_id"
    
    echo "" >&3
    echo "✅ Safe mode validation complete for $display_name" >&3
    echo "" >&3
    
    debug_function_exit "$function_name" "Success"
    echo "$new_uuid"
    return 0
}

detect_safe_mode_apps() {
    local workspace_name="$1"
    local script_path="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
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
    local app_count=${#apps[@]}
    
    debug_function_enter "$function_name" "App count: $app_count"
    debug_array "apps"
    
    # Display header
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "⚠️  SAFE MODE RECOMMENDED" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "The following applications have not been validated yet:" >&3
    echo "" >&3
    
    # List applications with display names and commands
    for app_id in "${apps[@]}"; do
        local display_name
        display_name=$(db_get_app_display_name "$app_id")
        echo "  • $app_id ($display_name)" >&3
        echo "    Command: kdoitall app safe-mode $app_id" >&3
    done
    
    echo "" >&3
    echo "Safe mode guides you through a controlled launch to ensure" >&3
    echo "reliable window detection. This only needs to be done ONCE" >&3
    echo "per application." >&3
    echo "" >&3
    echo "You can run safe mode for each app using the commands above," >&3
    echo "or choose one of these options:" >&3
    echo "" >&3
    echo "Options:" >&3
    echo "  [E] End workspace open (recommended - run safe mode first)" >&3
    echo "  [O] Open workspace anyway (will ask again next time)" >&3
    echo "  [S] Skip these apps (don't ask again for these specific apps)" >&3
    echo "  [N] Never ask for safe mode again (disable for all apps)" >&3
    echo "" >&3
    
    # Get user choice
    local choice
    read -r -p "Choice: " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
}

prepare_safe_mode_environment() {
    local function_name="prepare_safe_mode_environment"
    
    debug_function_enter "$function_name"
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "📋 SAFE MODE PREPARATION" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "For best results (but not required):" >&3
    echo "" >&3
    echo "1. Close other applications, especially any that match" >&3
    echo "   the app being launched" >&3
    echo "" >&3
    echo "2. Use a standalone terminal application, NOT a terminal" >&3
    echo "   embedded in another app (like VS Code's integrated terminal)" >&3
    echo "" >&3
    
    # Show current windows using auto_detect_windows and display function
    echo "Current windows on your system:" >&3
    echo "" >&3
    auto_detect_windows
    display_tracked_windows
    
    echo "" >&3
    echo "TIP: You can note which window is your current terminal" >&3
    echo "     to help with verification later." >&3
    echo "" >&3
    
    read -r -p "Press [Enter] when ready, or [C] to cancel: " ready
    ready=$(echo "$ready" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$ready" == "c" ]]; then
        debug_function_exit "$function_name" "User cancelled"
        return 1
    fi
    
    debug_function_exit "$function_name" "Environment prepared"
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
    display_name=$(db_get_app_display_name "$app_id")
    
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

    # Close window
    minimize_window "$uuid"
    
    echo "" >&3
    echo "✓ Window detected after ${elapsed_ms}ms" >&3
    echo "" >&3
    
    # Store measurement in database
    db_set_launch_time "$app_id" "$elapsed_ms"
    
    # Get updated statistics
    local expected_time
    local sample_count
    expected_time=$(db_get_launch_time "$app_id")
    sample_count=$(db_get_launch_time_samples "$app_id")
    
    echo "Launch Time Statistics:" >&3
    echo "  Measured time: ${elapsed_ms}ms" >&3
    echo "  Expected time: ${expected_time}ms (based on $sample_count sample(s))" >&3
    echo "" >&3
    echo "Future launches will wait up to ${expected_time}ms for this application." >&3
    echo "" >&3
    
    debug_log "$function_name" "Launch time measured: ${elapsed_ms}ms, expected: ${expected_time}ms"
    debug_function_exit "$function_name"

    # ADD THESE LINES FOR DEBUGGING:
    # echo "About to echo UUID: $uuid" >> /tmp/kdoitall_debug.log
    echo "$uuid"
    # echo "Echoed UUID, about to return" >> /tmp/kdoitall_debug.log
    return 0
}

safe_mode_verify_window() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_verify_window"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    # Get window metadata
    local class
    local title
    local display_name
    class=$(get_window_class "$uuid")
    title=$(get_window_title "$uuid")
    display_name=$(db_get_app_display_name "$app_id")
    
    # Display detection results
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "✅ WINDOW DETECTED" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Application: $display_name ($app_id)" >&3
    echo "Window UUID: $uuid" >&3
    echo "Window Class: $class" >&3
    echo "Window Title: $title" >&3
    echo "" >&3
    
    # Ask for confirmation
    local confirmed
    read -r -p "Is this the correct window for $display_name? [Y/n]: " confirmed
    confirmed=$(echo "$confirmed" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$confirmed" == "n" ]]; then
        echo "" >&3
        echo "❌ Window rejected by user" >&3
        debug_function_exit "$function_name" "Rejected"
        return 1
    fi
    
    echo "" >&3
    echo "✓ Window confirmed" >&3
    
    debug_function_exit "$function_name" "Confirmed"
    return 0
}

safe_mode_analyze_title_pattern() {
    local app_id="$1"
    local uuid="$2"
    local current_title="$3"
    local function_name="safe_mode_analyze_title_pattern"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    validate_parameter_pass "$current_title" "current_title" || return 1
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "📝 WINDOW TITLE PATTERN" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Current window title: \"$current_title\"" >&3
    echo "" >&3
    
    # Parse title to get suggestions
    local -a suggestions=()
    mapfile -t suggestions < <(parse_window_title_segments "$current_title")
    
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        echo "No separators found in the window title." >&3
        echo "The title doesn't contain ' - ' or ' — ' separators." >&3
        echo "" >&3
        echo "You can still enter a custom pattern if you want." >&3
        echo "" >&3
        read -r -p "Enter a unique pattern (or press Enter to skip): " pattern
        
        if [[ -z "$pattern" ]]; then
            echo "Skipping title pattern." >&3
            debug_function_exit "$function_name" "Skipped - no pattern entered"
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
                debug_function_exit "$function_name" "Rejected - pattern not in title"
                return 0
            fi
        fi
        
        # Save the pattern
        db_set_window_title_pattern "$app_id" "$pattern"
        echo "" >&3
        echo "✓ Title pattern saved: \"$pattern\"" >&3
        echo "  This pattern will match any window title containing: $pattern" >&3
        
        debug_log "$function_name" "Custom pattern saved: $pattern"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # We have suggestions - display them
    echo "Based on the window title structure, here are suggested patterns:" >&3
    echo "" >&3
    echo "Suggestions (starting with rightmost):" >&3
    
    local i=1
    for suggestion in "${suggestions[@]}"; do
        echo "  [$i] \"$suggestion\"" >&3
        ((i++))
    done
    
    echo "  [$i] Custom pattern (enter your own)" >&3
    local custom_option=$i
    echo "" >&3
    echo "These patterns help kdoitall identify this application's windows" >&3
    echo "by matching unique parts of the window title." >&3
    echo "" >&3
    
    # Get user choice
    local choice
    read -r -p "Select a pattern (1-$i) or press Enter to skip: " choice
    
    # If user pressed Enter, skip
    if [[ -z "$choice" ]]; then
        echo "Skipping title pattern." >&3
        debug_function_exit "$function_name" "Skipped by user"
        return 0
    fi
    
    # Validate choice is a number
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Invalid choice. Skipping title pattern." >&3
        debug_function_exit "$function_name" "Invalid input"
        return 0
    fi
    
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
    
    # Save the pattern
    db_set_window_title_pattern "$app_id" "$pattern"
    
    echo "" >&3
    echo "✓ Title pattern saved: \"$pattern\"" >&3
    echo "  This pattern will match any window title containing: $pattern" >&3
    
    debug_log "$function_name" "Title pattern saved: $pattern"
    debug_function_exit "$function_name"
    return 0
}

safe_mode_test_pid_validation() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_test_pid_validation"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$uuid" "uuid" || return 1
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "🔬 PID VALIDATION TEST" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Testing if PID-based validation is available for this application..." >&3
    echo "" >&3
    
    # Get PID from window
    local pid
    pid=$(get_window_pid "$uuid")
    
    if [[ -z "$pid" ]]; then
        echo "✗ PID not available for this application" >&3
        echo "" >&3
        echo "This means the window manager doesn't provide PID information" >&3
        echo "for this application. PID-based validation will not be used." >&3
        
        # Store that PID validation is not supported
        db_set_pid_validation_data "$app_id" "false" "" ""
        
        echo "" >&3
        read -r -p "Press [Enter] to continue..."
        
        debug_log "$function_name" "PID validation not supported for $app_id"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Get process information
    local process_name
    local executable_path
    
    process_name=$(get_process_name "$pid")
    executable_path=$(get_executable_path "$pid")
    
    # Display findings
    echo "✓ PID available: $pid" >&3
    echo "" >&3
    echo "Process Information:" >&3
    echo "  Process Name: $process_name" >&3
    echo "  Executable:   $executable_path" >&3
    echo "" >&3
    echo "This information can be used in the future to verify that" >&3
    echo "detected windows belong to the correct application." >&3
    echo "" >&3
    
    # Ask user to verify the information
    local verified
    read -r -p "Does this information look correct for $app_id? [Y/n]: " verified
    verified=$(echo "$verified" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$verified" == "n" ]]; then
        echo "" >&3
        echo "❌ PID validation data rejected by user" >&3
        echo "" >&3
        echo "PID validation will be marked as unsupported for this application." >&3
        
        # Store that PID validation is not supported
        db_set_pid_validation_data "$app_id" "false" "" ""
        
        debug_log "$function_name" "PID validation rejected by user for $app_id"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Store validation data
    db_set_pid_validation_data "$app_id" "true" "$process_name" "$executable_path"
    
    echo "" >&3
    echo "✓ PID validation data stored successfully" >&3
    echo "" >&3
    
    debug_log "$function_name" "PID validation enabled for $app_id: process='$process_name', path='$executable_path'"
    debug_function_exit "$function_name"
    return 0
}

safe_mode_test_multi_instance() {
    local app_id="$1"
    local existing_uuid="$2"
    local function_name="safe_mode_test_multi_instance"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    validate_parameter_pass "$existing_uuid" "existing_uuid" || return 1
    
    # Get display name
    local display_name=""
    display_name=$(db_get_app_display_name "$app_id")

    local class=""
    class=$(db_get_app_class "$app_id")
    
    # Prompt user
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "🔬 MULTI-INSTANCE TEST" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Testing if $display_name allows multiple windows..." >&3
    echo "" >&3
    echo "This test will:" >&3
    echo "  1. Launch a second instance of the application" >&3
    echo "  2. Check if a new window appears" >&3
    echo "  3. Store the result for future launches" >&3
    echo "" >&3
    
    # Refresh database before launch
    echo "Scanning existing windows..." >&3
    auto_detect_windows
    
    # Launch second instance
    echo "Launching second instance of $display_name..." >&3
    (gtk-launch "$app_id" &>/dev/null &)
    
    # Wait and detect new window with cancellation support
    echo "Waiting for new window to appear..." >&3
    echo "(Press 'c' + Enter at any time to cancel)" >&3
    echo "" >&3

    local new_uuid=""
    local max_attempts=60  # 30 seconds at 0.5s intervals
    local attempt=0
    local user_cancelled=false

    while (( attempt < max_attempts )); do
        # Check for user cancellation (non-blocking)
        if read -t 0.5 -n 1 -r input 2>/dev/null; then
            if [[ "$input" == "c" || "$input" == "C" ]]; then
                echo "" >&3
                echo "User cancelled window detection." >&3
                user_cancelled=true
                break
            fi
        fi
        
        # Try to detect new window
        new_uuid=$(get_uuid_by_process_of_elimination "$class" "TRUE")
        
        if [[ -n "$new_uuid" ]]; then
            echo "" >&3
            echo "✓ New window detected after $((attempt / 2))s" >&3
            break
        fi
        
        # Progress indicator every 10 attempts (5 seconds)
        if (( attempt > 0 && attempt % 10 == 0 )); then
            echo "Still waiting... ($((attempt / 2))s elapsed)" >&3
        fi
        
        ((attempt++))
    done

    # Handle timeout
    if [[ -z "$new_uuid" && "$user_cancelled" == false ]]; then
        echo "" >&3
        echo "No new window detected after 30s" >&3
    fi

    if [[ "$user_cancelled" == true ]]; then
        echo "Assuming NO new window appeared (single-instance mode)" >&3
    fi

    minimize_window "$new_uuid"
    
    local detected_mode=""
    if [[ -n "$new_uuid" ]]; then
        detected_mode="multi"
    else
        detected_mode="single"
    fi
    
    # Display result to user
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "📊 TEST RESULTS" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    
    if [[ "$detected_mode" == "multi" ]]; then
        echo "✓ New window detected: $new_uuid" >&3
        echo "" >&3
        echo "DETERMINATION: Application supports MULTIPLE instances" >&3
        echo "  → Multiple windows of $display_name can run simultaneously" >&3
    else
        echo "✗ No new window detected" >&3
        echo "" >&3
        echo "DETERMINATION: Application supports SINGLE instance only" >&3
        echo "  → Only one window of $display_name can run at a time" >&3
        echo "  → Launching again will focus the existing window" >&3
    fi
    
    echo "" >&3

    if [[ "$detected_mode" == "single" ]]; then
        # Test if it's actually UNIQUE mode
        detected_mode=$(safe_mode_test_for_unique_mode "$app_id" "$existing_uuid")
    fi
    
    # PID Verification for Multi-Instance Apps
    if [[ "$detected_mode" == "multi" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "🔬 PID VERIFICATION" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3
        echo "Checking if PIDs can be used to distinguish between windows..." >&3
        echo "" >&3
        
        # Get PID from first window (existing_uuid)
        local first_pid=""
        first_pid=$(get_window_pid "$existing_uuid" 2>/dev/null)
        
        # Get PID from second window (new_uuid)
        local second_pid=""
        second_pid=$(get_window_pid "$new_uuid" 2>/dev/null)
        
        # Check if both PIDs are available
        if [[ -z "$first_pid" || -z "$second_pid" ]]; then
            echo "⚠️  Could not retrieve PIDs for one or both windows" >&3
            echo "   First window PID:  ${first_pid:-<not available>}" >&3
            echo "   Second window PID: ${second_pid:-<not available>}" >&3
            echo "" >&3
            echo "→ PID validation will be marked as UNSUPPORTED for this app" >&3
            echo "" >&3
            
            # Mark PID validation as unsupported
            db_set_pid_validation_data "$app_id" "false" "" ""
        elif [[ "$first_pid" == "$second_pid" ]]; then
            # Same PID for both windows - cannot use PID for validation
            echo "⚠️  Both windows share the SAME PID: $first_pid" >&3
            echo "" >&3
            echo "This is common for applications like:" >&3
            echo "  • VS Code (Electron-based apps)" >&3
            echo "  • Chrome/Chromium-based browsers" >&3
            echo "  • Some multi-window IDEs" >&3
            echo "" >&3
            echo "→ PID validation will be marked as UNSUPPORTED for this app" >&3
            echo "→ Window detection will rely on class and title patterns instead" >&3
            echo "" >&3
            
            # Mark PID validation as unsupported
            db_set_pid_validation_data "$app_id" "false" "" ""
        else
            # Different PIDs - can use PID for validation
            echo "✓ Different PIDs detected:" >&3
            echo "   First window PID:  $first_pid" >&3
            echo "   Second window PID: $second_pid" >&3
            echo "" >&3
            echo "→ PID validation CAN be used for this application" >&3
            echo "" >&3
        fi
    fi
    
    echo ""
    
    # Ask user to confirm the determination
    local confirmed
    read -r -p "Is this determination correct? [Y/n]: " confirmed
    confirmed=$(echo "$confirmed" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$confirmed" == "n" ]]; then
        echo "" >&3
        echo "User rejected the determination." >&3
        echo "Please manually set the launch mode later if needed." >&3
        
        # Clean up second window if it exists
        if [[ -n "$new_uuid" ]]; then
            echo "Closing second window..." >&3
            close_window "$new_uuid"
        fi
        
        debug_function_exit "$function_name" "Rejected"
        return 0
    fi
    
    # Store result in database
    echo "" >&3
    echo "Storing launch mode: $detected_mode" >&3
    db_set_launch_mode "$app_id" "$detected_mode"
    
    # Close second window if multi-instance was detected
    if [[ "$detected_mode" == "multi" && -n "$new_uuid" ]]; then
        echo "Closing second window..." >&3
        close_window "$new_uuid"
    fi
    
    echo "✓ Multi-instance test complete" >&3
    
    debug_function_exit "$function_name"
    return 0
}

safe_mode_test_for_unique_mode() {
    local app_id="$1"
    local existing_uuid="$2"
    local function_name="safe_mode_test_for_unique_mode"
    
    debug_function_enter "$function_name" "$@"
    
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "🔬 UNIQUE MODE TEST" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "No new window appeared with default launch." >&3
    echo "" >&3
    echo "This could mean:" >&3
    echo "  1. SINGLE mode: Only one window allowed (e.g., Settings)" >&3
    echo "  2. UNIQUE mode: Multiple windows allowed if state differs" >&3
    echo "" >&3
    echo "Examples of UNIQUE mode applications:" >&3
    echo "  • VS Code: Opens new window if you open a different folder" >&3
    echo "  • Firefox: Opens new window with different profile" >&3
    echo "  • File managers: Sometimes open new window for different locations" >&3
    echo "" >&3
    echo "We'll test if $display_name supports UNIQUE mode by letting you" >&3
    echo "change the application's state before we try launching again." >&3
    echo "" >&3
    
    local attempt=1
    local max_attempts=5
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "Attempt $attempt of $max_attempts" >&3
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
        echo "" >&3
        echo "Instructions:" >&3
        echo "  1. Switch to the $display_name window" >&3
        echo "  2. Change its state (examples below)" >&3
        echo "  3. Return to this terminal" >&3
        echo "  4. Press [Enter] to test launch" >&3
        echo "" >&3
        echo "Ways to change application state:" >&3
        echo "  • Open a different file/folder" >&3
        echo "  • Navigate to a different location" >&3
        echo "  • Change workspace/profile/project" >&3
        echo "  • Close any open documents" >&3
        echo "  • Change view/mode (if applicable)" >&3
        echo "" >&3
        
        # Get current window title as reference
        local current_title
        current_title=$(get_window_title "$existing_uuid")
        echo "Current window title: \"$current_title\"" >&3
        echo "" >&3
        
        read -r -p "Ready to test? [Enter] or [S]kip to accept SINGLE mode: " ready
        ready=$(echo "$ready" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$ready" == "s" ]]; then
            echo "" >&3
            echo "User skipped UNIQUE mode testing" >&3
            echo "Determination: LAUNCH_MODE_SINGLE" >&3
            debug_function_exit "$function_name" "SINGLE"
            echo "single"
            return 0
        fi
        
        # Refresh window tracking
        echo "" >&3
        echo "Scanning existing windows..." >&3
        auto_detect_windows
        
        # Attempt launch
        echo "Launching $display_name..." >&3
        (gtk-launch "$app_id" &>/dev/null &)
        
        # Wait for new window
        echo "Waiting for new window (10 seconds)..." >&3
        local new_uuid
        new_uuid=$(get_uuid_by_process_of_elimination_with_retry "" 10 0.1)
        
        if [[ -n "$new_uuid" ]]; then
            # Success! New window appeared
            echo "" >&3
            echo "✓ New window detected: $new_uuid" >&3
            
            # Get new window title for comparison
            local new_title
            new_title=$(get_window_title "$new_uuid")
            
            echo "" >&3
            echo "Window Comparison:" >&3
            echo "  Original: \"$current_title\"" >&3
            echo "  New:      \"$new_title\"" >&3
            echo "" >&3
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
            echo "✅ DETERMINATION: LAUNCH_MODE_UNIQUE" >&3
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
            echo "" >&3
            echo "$display_name supports multiple windows when state differs" >&3
            echo "" >&3
            
            # Clean up the new window
            echo "Closing new test window..." >&3
            close_window "$new_uuid"
            
            debug_function_exit "$function_name" "UNIQUE"
            echo "unique"
            return 0
        else
            # No new window
            echo "" >&3
            echo "✗ No new window detected" >&3
            echo "" >&3
            echo "Either:" >&3
            echo "  • The application state didn't change enough" >&3
            echo "  • The application truly is SINGLE mode" >&3
            echo "" >&3
            
            if [[ $attempt -lt $max_attempts ]]; then
                read -r -p "Try again with different state? [Y/n]: " retry
                retry=$(echo "$retry" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

                if [[ "$retry" != "y" && "$retry" != "yes" && "$retry" != "" ]]; then
                    # Anything other than y/yes/Enter means stop
                    echo "" >&3
                    echo "User accepted SINGLE mode determination" >&3
                    debug_function_exit "$function_name" "SINGLE"
                    echo "single"
                    return 0
                fi
            fi
        fi
        
        ((attempt++))
        echo "" >&3
    done
    
    # Exhausted all attempts
    echo "" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "Maximum attempts reached" >&3
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&3
    echo "" >&3
    echo "Determination: LAUNCH_MODE_SINGLE" >&3
    
    debug_function_exit "$function_name" "SINGLE"
    echo "single"
    return 0
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