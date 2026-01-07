#!/bin/bash

check_and_set_guard "_KDOITALL_APP_SAFE_MODE_LOADED" || return 0

# Source required modules
# shellcheck source=../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../db/safe-mode.sh
source "${LIB_DIR}/db/safe-mode.sh"
# shellcheck source=../utils/display.sh
source "${LIB_DIR}/utils/display.sh"
# shellcheck source=../core/core.sh
source "${LIB_DIR}/core/core.sh"
# shellcheck source=../window-management/window.sh
source "${LIB_DIR}/window-management/window.sh"

detect_safe_mode_apps() {
    local workspace_name="$1"
    local script_path="${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
    local function_name="detect_safe_mode_apps"
    local -a safe_mode_apps=()
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" || return 1
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
    
    # Display header
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  SAFE MODE RECOMMENDED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The following applications have not been validated yet:"
    echo ""
    
    # List applications with display names and commands
    for app_id in "${apps[@]}"; do
        local display_name
        display_name=$(db_get_app_display_name "$app_id")
        echo "  • $app_id ($display_name)"
        echo "    Command: kdoitall app safe-mode $app_id"
    done
    
    echo ""
    echo "Safe mode guides you through a controlled launch to ensure"
    echo "reliable window detection. This only needs to be done ONCE"
    echo "per application."
    echo ""
    echo "You can run safe mode for each app using the commands above,"
    echo "or choose one of these options:"
    echo ""
    echo "Options:"
    echo "  [E] End workspace open (recommended - run safe mode first)"
    echo "  [O] Open workspace anyway (will ask again next time)"
    echo "  [S] Skip these apps (don't ask again for these specific apps)"
    echo "  [N] Never ask for safe mode again (disable for all apps)"
    echo ""
    
    # Get user choice
    local choice
    read -r -p "Choice: " choice
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    
    debug_function_exit "$function_name" "User chose: $choice"
    echo "$choice"
}

prepare_safe_mode_environment() {
    local function_name="prepare_safe_mode_environment"
    
    debug_function_enter "$function_name"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 SAFE MODE PREPARATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "For best results (but not required):"
    echo ""
    echo "1. Close other applications, especially any that match"
    echo "   the app being launched"
    echo ""
    echo "2. Use a standalone terminal application, NOT a terminal"
    echo "   embedded in another app (like VS Code's integrated terminal)"
    echo ""
    
    # Show current windows using auto_detect_windows and display function
    echo "Current windows on your system:"
    echo ""
    auto_detect_windows
    display_tracked_windows
    
    echo ""
    echo "TIP: You can note which window is your current terminal"
    echo "     to help with verification later."
    echo ""
    
    read -r -p "Press [Enter] when ready, or [C] to cancel: " ready
    ready=$(echo "$ready" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$ready" == "c" ]]; then
        debug_function_exit "$function_name" "User cancelled"
        return 1
    fi
    
    debug_function_exit "$function_name" "Environment prepared"
    return 0
}

safe_mode_verify_window() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_verify_window"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$uuid" || return 1
    
    # Get window metadata
    local class
    local title
    local display_name
    class=$(get_window_class_by_uuid "$uuid")
    title=$(get_window_title_by_uuid "$uuid")
    display_name=$(db_get_app_display_name "$app_id")
    
    # Display detection results
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ WINDOW DETECTED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Application: $display_name ($app_id)"
    echo "Window UUID: $uuid"
    echo "Window Class: $class"
    echo "Window Title: $title"
    echo ""
    
    # Ask for confirmation
    local confirmed
    read -r -p "Is this the correct window for $display_name? [Y/n]: " confirmed
    confirmed=$(echo "$confirmed" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$confirmed" == "n" ]]; then
        echo ""
        echo "❌ Window rejected by user"
        debug_function_exit "$function_name" "Rejected"
        return 1
    fi
    
    echo ""
    echo "✓ Window confirmed"
    
    debug_function_exit "$function_name" "Confirmed"
    return 0
}

safe_mode_store_metadata() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_store_metadata"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$uuid" || return 1
    
    # Extract metadata
    local class
    class=$(get_window_class_by_uuid "$uuid")
    
    # Store class in database using db function
    db_set_app_class "$app_id" "$class"
    
    debug_log "$function_name" "Stored: class=$class"
    
    echo ""
    echo "✓ Metadata stored successfully:"
    echo "  • Class: $class"
    
    debug_function_exit "$function_name"
    return 0
}

safe_mode_test_multi_instance() {
    local app_id="$1"
    local existing_uuid="$2"
    local function_name="safe_mode_test_multi_instance"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$existing_uuid" || return 1
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    # Prompt user
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔬 MULTI-INSTANCE TEST"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Testing if $display_name allows multiple windows..."
    echo ""
    echo "This test will:"
    echo "  1. Launch a second instance of the application"
    echo "  2. Check if a new window appears"
    echo "  3. Store the result for future launches"
    echo ""
    
    # Refresh database before launch
    echo "Scanning existing windows..."
    auto_detect_windows
    
    # Launch second instance
    echo "Launching second instance of $display_name..."
    gtk-launch "$app_id" &
    
    # Wait and detect new window using retry function
    echo "Waiting for new window to appear..."
    local new_uuid=""
    new_uuid=$(get_uuid_by_process_of_elimination_with_retry "" 30 0.1)
    
    local detected_mode=""
    if [[ -n "$new_uuid" ]]; then
        detected_mode="multi"
    else
        detected_mode="single"
    fi
    
    # Display result to user
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 TEST RESULTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ "$detected_mode" == "multi" ]]; then
        echo "✓ New window detected: $new_uuid"
        echo ""
        echo "DETERMINATION: Application supports MULTIPLE instances"
        echo "  → Multiple windows of $display_name can run simultaneously"
    else
        echo "✗ No new window detected"
        echo ""
        echo "DETERMINATION: Application supports SINGLE instance only"
        echo "  → Only one window of $display_name can run at a time"
        echo "  → Launching again will focus the existing window"
    fi
    
    echo ""
    
    # PID Verification for Multi-Instance Apps
    if [[ "$detected_mode" == "multi" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🔬 PID VERIFICATION"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Checking if PIDs can be used to distinguish between windows..."
        echo ""
        
        # Get PID from first window (existing_uuid)
        local first_pid=""
        first_pid=$(get_window_pid_by_uuid "$existing_uuid" 2>/dev/null)
        
        # Get PID from second window (new_uuid)
        local second_pid=""
        second_pid=$(get_window_pid_by_uuid "$new_uuid" 2>/dev/null)
        
        # Check if both PIDs are available
        if [[ -z "$first_pid" || -z "$second_pid" ]]; then
            echo "⚠️  Could not retrieve PIDs for one or both windows"
            echo "   First window PID:  ${first_pid:-<not available>}"
            echo "   Second window PID: ${second_pid:-<not available>}"
            echo ""
            echo "→ PID validation will be marked as UNSUPPORTED for this app"
            echo ""
            
            # Mark PID validation as unsupported
            db_set_pid_validation_data "$app_id" "false" "" ""
        elif [[ "$first_pid" == "$second_pid" ]]; then
            # Same PID for both windows - cannot use PID for validation
            echo "⚠️  Both windows share the SAME PID: $first_pid"
            echo ""
            echo "This is common for applications like:"
            echo "  • VS Code (Electron-based apps)"
            echo "  • Chrome/Chromium-based browsers"
            echo "  • Some multi-window IDEs"
            echo ""
            echo "→ PID validation will be marked as UNSUPPORTED for this app"
            echo "→ Window detection will rely on class and title patterns instead"
            echo ""
            
            # Mark PID validation as unsupported
            db_set_pid_validation_data "$app_id" "false" "" ""
        else
            # Different PIDs - can use PID for validation
            echo "✓ Different PIDs detected:"
            echo "   First window PID:  $first_pid"
            echo "   Second window PID: $second_pid"
            echo ""
            echo "→ PID validation CAN be used for this application"
            echo "→ The standard PID validation test will run later"
            echo ""
        fi
    fi
    
    echo ""
    
    # Ask user to confirm the determination
    local confirmed
    read -r -p "Is this determination correct? [Y/n]: " confirmed
    confirmed=$(echo "$confirmed" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$confirmed" == "n" ]]; then
        echo ""
        echo "User rejected the determination."
        echo "Please manually set the launch mode later if needed."
        
        # Clean up second window if it exists
        if [[ -n "$new_uuid" ]]; then
            echo "Closing second window..."
            close_window_by_uuid "$new_uuid"
        fi
        
        debug_function_exit "$function_name" "Rejected"
        return 0
    fi
    
    # Store result in database
    echo ""
    echo "Storing launch mode: $detected_mode"
    db_set_launch_mode "$app_id" "$detected_mode"
    
    # Close second window if multi-instance was detected
    if [[ "$detected_mode" == "multi" && -n "$new_uuid" ]]; then
        echo "Closing second window..."
        close_window_by_uuid "$new_uuid"
    fi
    
    echo "✓ Multi-instance test complete"
    
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

    validate_parameter_pass "$app_id" || return 1
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⏱️  LAUNCH TIME MEASUREMENT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Application: $display_name ($app_id)"
    echo "Measuring launch time with generous timeout (30 seconds)..."
    echo ""
    
    # Refresh database before launch
    echo "Scanning existing windows..."
    auto_detect_windows

    # Record start time (milliseconds since epoch)
    start_time=$(date +%s%3N)
    
    # Launch application
    echo "Launching $display_name..."
    gtk-launch "$app_id" &
    
    # Wait for window with extended timeout using retry function
    echo "Waiting for window to appear (timeout: 30 seconds)..."
    echo ""
    
    # Use get_uuid_by_process_of_elimination_with_retry with 30 second timeout
    local uuid
    uuid=$(get_uuid_by_process_of_elimination_with_retry "" 30 0.1)
    
    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_NOT_FOUND" "Launch time measurement failed - no window detected"
        echo ""
        echo "❌ Could not measure launch time - window not detected within 30 seconds"
        echo ""
        echo "This usually means:"
        echo "  • Application failed to launch"
        echo "  • Application takes longer than 30 seconds to start"
        echo "  • Application is already running (single-instance)"
        echo ""
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Record end time
    end_time=$(date +%s%3N)
    
    # Calculate elapsed time in milliseconds
    elapsed_ms=$((end_time - start_time))
    
    echo ""
    echo "✓ Window detected after ${elapsed_ms}ms"
    echo ""
    
    # Store measurement in database
    db_set_launch_time "$app_id" "$elapsed_ms"
    
    # Get updated statistics
    local expected_time
    local sample_count
    expected_time=$(db_get_expected_launch_time "$app_id")
    sample_count=$(db_get_launch_time_samples "$app_id")
    
    echo "Launch Time Statistics:"
    echo "  Measured time: ${elapsed_ms}ms"
    echo "  Expected time: ${expected_time}ms (based on $sample_count sample(s))"
    echo ""
    echo "Future launches will wait up to ${expected_time}ms for this application."
    echo ""
    
    debug_log "$function_name" "Launch time measured: ${elapsed_ms}ms, expected: ${expected_time}ms"
    debug_function_exit "$function_name"
    echo "$uuid"  # Return detected UUID for continued safe mode flow
    return 0
}

safe_mode_launch_and_detect() {
    local app_id="$1"
    local function_name="safe_mode_launch_and_detect"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    # Use launch time measurement for detection
    local new_uuid
    new_uuid=$(safe_mode_measure_launch_time "$app_id")
    
    # Check if measurement succeeded
    if [[ -z "$new_uuid" ]]; then
        # Launch time measurement failed - offer recovery options
        echo ""
        echo "Options:"
        echo "  [R] Retry launch"
        echo "  [S] Skip this application"
        echo ""
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
        echo ""
        echo "Options:"
        echo "  [R] Retry launch"
        echo "  [S] Skip this application"
        echo ""
        read -r -p "Choice: " recovery
        recovery=$(echo "$recovery" | tr '[:upper:]' '[:lower:]')
        
        case "$recovery" in
            r)
                # Close the wrong window first
                close_window_by_uuid "$new_uuid"
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
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 GATHERING METADATA"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Test PID-based validation
    safe_mode_test_pid_validation "$app_id" "$new_uuid"
    
    # Analyze window title pattern
    local title
    title=$(get_window_title_by_uuid "$new_uuid")
    safe_mode_analyze_title_pattern "$app_id" "$new_uuid" "$title"
    
    # Test multi-instance support
    safe_mode_test_multi_instance "$app_id" "$new_uuid"
    
    echo ""
    echo "✓ Metadata collection complete"
    
    # Mark safe mode as complete
    db_set_safe_mode_completed "$app_id"
    
    echo ""
    echo "✅ Safe mode validation complete for $display_name"
    echo ""
    
    debug_function_exit "$function_name" "Success"
    echo "$new_uuid"
    return 0
}

safe_mode_test_pid_validation() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_test_pid_validation"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$uuid" || return 1
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔬 PID VALIDATION TEST"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Testing if PID-based validation is available for this application..."
    echo ""
    
    # Get PID from window
    local pid
    pid=$(get_window_pid_by_uuid "$uuid")
    
    if [[ -z "$pid" ]]; then
        echo "✗ PID not available for this application"
        echo ""
        echo "This means the window manager doesn't provide PID information"
        echo "for this application. PID-based validation will not be used."
        
        # Store that PID validation is not supported
        db_set_pid_validation_data "$app_id" "false" "" ""
        
        echo ""
        read -r -p "Press [Enter] to continue..."
        
        debug_log "$function_name" "PID validation not supported for $app_id"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Get process information
    local process_name
    local executable_path
    
    process_name=$(get_process_name_by_pid "$pid")
    executable_path=$(get_executable_path_by_pid "$pid")
    
    # Display findings
    echo "✓ PID available: $pid"
    echo ""
    echo "Process Information:"
    echo "  Process Name: $process_name"
    echo "  Executable:   $executable_path"
    echo ""
    echo "This information can be used in the future to verify that"
    echo "detected windows belong to the correct application."
    echo ""
    
    # Ask user to verify the information
    local verified
    read -r -p "Does this information look correct for $app_id? [Y/n]: " verified
    verified=$(echo "$verified" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$verified" == "n" ]]; then
        echo ""
        echo "❌ PID validation data rejected by user"
        echo ""
        echo "PID validation will be marked as unsupported for this application."
        
        # Store that PID validation is not supported
        db_set_pid_validation_data "$app_id" "false" "" ""
        
        debug_log "$function_name" "PID validation rejected by user for $app_id"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Store validation data
    db_set_pid_validation_data "$app_id" "true" "$process_name" "$executable_path"
    
    echo ""
    echo "✓ PID validation data stored successfully"
    echo ""
    
    debug_log "$function_name" "PID validation enabled for $app_id: process='$process_name', path='$executable_path'"
    debug_function_exit "$function_name"
    return 0
}

safe_mode_analyze_title_pattern() {
    local app_id="$1"
    local uuid="$2"
    local current_title="$3"
    local function_name="safe_mode_analyze_title_pattern"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" || return 1
    validate_parameter_pass "$uuid" || return 1
    validate_parameter_pass "$current_title" || return 1
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📝 WINDOW TITLE PATTERN"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Current window title: \"$current_title\""
    echo ""
    
    # Parse title to get suggestions
    local -a suggestions=()
    mapfile -t suggestions < <(parse_window_title_segments "$current_title")
    
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        echo "No separators found in the window title."
        echo "The title doesn't contain ' - ' or ' — ' separators."
        echo ""
        echo "You can still enter a custom pattern if you want."
        echo ""
        read -r -p "Enter a unique pattern (or press Enter to skip): " pattern
        
        if [[ -z "$pattern" ]]; then
            echo "Skipping title pattern."
            debug_function_exit "$function_name" "Skipped - no pattern entered"
            return 0
        fi
        
        # Validate custom pattern exists in title
        if [[ ! "$current_title" =~ $pattern ]]; then
            echo ""
            echo "⚠️  Warning: Pattern \"$pattern\" not found in current title!"
            read -r -p "Save anyway? [y/N]: " save_anyway
            save_anyway=$(echo "$save_anyway" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$save_anyway" != "y" ]]; then
                echo "Pattern not saved."
                debug_function_exit "$function_name" "Rejected - pattern not in title"
                return 0
            fi
        fi
        
        # Save the pattern
        db_set_title_pattern "$app_id" "$pattern"
        echo ""
        echo "✓ Title pattern saved: \"$pattern\""
        echo "  This pattern will match any window title containing: $pattern"
        
        debug_log "$function_name" "Custom pattern saved: $pattern"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # We have suggestions - display them
    echo "Based on the window title structure, here are suggested patterns:"
    echo ""
    echo "Suggestions (starting with rightmost):"
    
    local i=1
    for suggestion in "${suggestions[@]}"; do
        echo "  [$i] \"$suggestion\""
        ((i++))
    done
    
    echo "  [$i] Custom pattern (enter your own)"
    local custom_option=$i
    echo ""
    echo "These patterns help kdoitall identify this application's windows"
    echo "by matching unique parts of the window title."
    echo ""
    
    # Get user choice
    local choice
    read -r -p "Select a pattern (1-$i) or press Enter to skip: " choice
    
    # If user pressed Enter, skip
    if [[ -z "$choice" ]]; then
        echo "Skipping title pattern."
        debug_function_exit "$function_name" "Skipped by user"
        return 0
    fi
    
    # Validate choice is a number
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Invalid choice. Skipping title pattern."
        debug_function_exit "$function_name" "Invalid input"
        return 0
    fi
    
    # Check if custom option was selected
    if [[ "$choice" -eq "$custom_option" ]]; then
        echo ""
        read -r -p "Enter custom pattern: " pattern
        
        if [[ -z "$pattern" ]]; then
            echo "No pattern entered. Skipping."
            debug_function_exit "$function_name" "No custom pattern entered"
            return 0
        fi
        
        # Validate custom pattern exists in title
        if [[ ! "$current_title" =~ $pattern ]]; then
            echo ""
            echo "⚠️  Warning: Pattern \"$pattern\" not found in current title!"
            read -r -p "Save anyway? [y/N]: " save_anyway
            save_anyway=$(echo "$save_anyway" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$save_anyway" != "y" ]]; then
                echo "Pattern not saved."
                debug_function_exit "$function_name" "Custom pattern rejected"
                return 0
            fi
        fi
    else
        # User selected a suggestion
        local suggestion_index=$((choice - 1))
        
        # Validate index is in range
        if [[ "$suggestion_index" -lt 0 || "$suggestion_index" -ge "${#suggestions[@]}" ]]; then
            echo "Invalid choice. Skipping title pattern."
            debug_function_exit "$function_name" "Choice out of range"
            return 0
        fi
        
        pattern="${suggestions[$suggestion_index]}"
    fi
    
    # Save the pattern
    db_set_title_pattern "$app_id" "$pattern"
    
    echo ""
    echo "✓ Title pattern saved: \"$pattern\""
    echo "  This pattern will match any window title containing: $pattern"
    
    debug_log "$function_name" "Title pattern saved: $pattern"
    debug_function_exit "$function_name"
    return 0
}
