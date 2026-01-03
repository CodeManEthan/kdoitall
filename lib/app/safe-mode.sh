#!/bin/bash

check_and_set_guard "_KDOITALL_APP_SAFE_MODE_LOADED" || return 0

# ============================================================================
# Safe Mode Core Functions
# ============================================================================
# Core safe mode logic for guided first-time application launches

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

# ----------------------------------------------------------------------------
# detect_safe_mode_apps()
# Scan workspace script to find apps needing safe mode validation
# Parameters:
#   $1 - workspace_name
# Returns: Newline-separated list of app_ids needing safe mode
# ----------------------------------------------------------------------------
detect_safe_mode_apps() {
    local workspace_name="$1"
    local script_path="$WORKSPACE_DIR/${workspace_name}-open.sh"
    local function_name="detect_safe_mode_apps"
    local -a safe_mode_apps=()
    
    debug_function_enter "$function_name" "$@"
    
    if [[ ! -f "$script_path" ]]; then
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "Workspace script not found: $script_path"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Parse workspace script to find all launch_by_app_id calls
    while IFS= read -r line; do
        if [[ "$line" =~ launch_by_app_id.*[[:space:]]\"([^\"]+)\" ]]; then
            local app_id="${BASH_REMATCH[1]}"
            
            # Check if app has custom file
            local has_custom_file=false
            if [[ -f "$LIB_DIR/applications/${app_id}.sh" ]]; then
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

# ----------------------------------------------------------------------------
# prompt_safe_mode()
# Display safe mode prompt and get user choice
# Parameters:
#   $@ - Array of app_ids needing safe mode
# Returns: User choice (e/o/s/n)
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# prepare_safe_mode_environment()
# Guide user through environment preparation for safe mode
# Returns: 0 if ready, 1 if cancelled
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# safe_mode_verify_window()
# Verify detected window with user
# Parameters:
#   $1 - app_id
#   $2 - uuid
# Returns: 0 if confirmed, 1 if rejected
# ----------------------------------------------------------------------------
safe_mode_verify_window() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_verify_window"
    
    debug_function_enter "$function_name" "$@"
    
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

# ----------------------------------------------------------------------------
# safe_mode_store_metadata()
# Store validated metadata for application
# Parameters:
#   $1 - app_id
#   $2 - uuid
# ----------------------------------------------------------------------------
safe_mode_store_metadata() {
    local app_id="$1"
    local uuid="$2"
    local function_name="safe_mode_store_metadata"
    
    debug_function_enter "$function_name" "$@"
    
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

# ----------------------------------------------------------------------------
# safe_mode_test_multi_instance()
# Test if application supports multiple instances
# Parameters:
#   $1 - app_id
#   $2 - existing_uuid (the UUID of the first instance)
# Returns: 0 on success (test completed or skipped), 1 on error
# ----------------------------------------------------------------------------
safe_mode_test_multi_instance() {
    local app_id="$1"
    local existing_uuid="$2"
    local function_name="safe_mode_test_multi_instance"
    
    debug_function_enter "$function_name" "$@"
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    # Prompt user
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔬 MULTI-INSTANCE TEST (Optional)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This test determines if $display_name allows multiple windows."
    echo ""
    echo "The test will:"
    echo "  1. Launch a second instance of the application"
    echo "  2. Check if a new window appears"
    echo "  3. Store the result for future launches"
    echo ""
    read -r -p "Run multi-instance test? [y/N]: " run_test
    run_test=$(echo "$run_test" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$run_test" != "y" ]]; then
        echo "Skipping multi-instance test."
        debug_function_exit "$function_name" "Skipped"
        return 0
    fi
    
    echo ""
    echo "Running multi-instance test..."
    
    # Refresh database before launch
    echo "Scanning existing windows..."
    auto_detect_windows
    
    # Launch second instance
    echo "Launching second instance of $display_name..."
    gtk-launch "$app_id" &
    
    # Wait for window to appear
    sleep "$LAUNCH_DELAY"
    
    # Refresh database after launch
    echo "Checking for new window..."
    auto_detect_windows
    
    # Detect new window using process of elimination
    local new_uuid=""
    new_uuid=$(get_uuid_by_process_of_elimination "")
    
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

# ----------------------------------------------------------------------------
# safe_mode_launch_and_detect()
# Launch application in controlled environment and detect window
# Parameters:
#   $1 - app_id
# Returns: UUID on success, exits with error on failure
# ----------------------------------------------------------------------------
safe_mode_launch_and_detect() {
    local app_id="$1"
    local function_name="safe_mode_launch_and_detect"
    
    debug_function_enter "$function_name" "$@"
    
    # Get display name
    local display_name
    display_name=$(db_get_app_display_name "$app_id")
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 LAUNCHING APPLICATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Application: $display_name ($app_id)"
    echo "Launch Command: gtk-launch $app_id"
    echo ""
    
    # Refresh database with current windows BEFORE launch
    echo "Scanning existing windows..."
    auto_detect_windows
    
    # Launch the application
    echo "Launching now..."
    gtk-launch "$app_id" &
    
    # Wait for window to appear
    echo ""
    echo "Waiting for window to appear..."
    sleep "$LAUNCH_DELAY"
    
    # Prompt user to confirm window appeared
    local window_appeared
    read -r -p "Did a window for $display_name appear? [Y/n]: " window_appeared
    window_appeared=$(echo "$window_appeared" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$window_appeared" == "n" ]]; then
        debug_error "$function_name" "$ERR_SAFE_MODE_NO_WINDOW" "User reports no window appeared"
        echo ""
        echo "❌ Window did not appear. Possible issues:"
        echo "   • Application failed to launch"
        echo "   • Application is already running (check for hidden windows)"
        echo "   • Desktop file is incorrect"
        echo ""
        echo "Options:"
        echo "  [R] Retry launch"
        echo "  [A] Abort safe mode"
        echo ""
        read -r -p "Choice: " recovery
        recovery=$(echo "$recovery" | tr '[:upper:]' '[:lower:]')
        
        case "$recovery" in
            r)
                debug_log "$function_name" "Retrying..."
                safe_mode_launch_and_detect "$app_id"
                return $?
                ;;
            *)
                debug_function_exit "$function_name" "Aborted"
                return 1
                ;;
        esac
    fi
    
    # Detect new window by process of elimination
    echo "Detecting new window..."
    
    # Refresh database again to get current state
    auto_detect_windows
    
    local new_uuid
    new_uuid=$(get_uuid_by_process_of_elimination "")
    
    if [[ -z "$new_uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "Process of elimination failed"
        echo ""
        echo "❌ Could not detect new window via process of elimination"
        echo "   This usually means:"
        echo "   • Multiple windows launched simultaneously"
        echo "   • No new window actually appeared"
        echo "   • Window closed immediately after launch"
        echo ""
        echo "Safe mode cannot continue. Aborting."
        debug_function_exit "$function_name" "Failed"
        return 1
    fi
    
    debug_log "$function_name" "Detected UUID: $new_uuid"
    
    # Verify detection with user
    if ! safe_mode_verify_window "$app_id" "$new_uuid"; then
        echo ""
        echo "Options:"
        echo "  [R] Retry launch"
        echo "  [A] Abort safe mode"
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
            *)
                debug_function_exit "$function_name" "Aborted"
                return 1
                ;;
        esac
    fi
    
    # Store validated data
    safe_mode_store_metadata "$app_id" "$new_uuid"
    
    # Run multi-instance test (optional)
    safe_mode_test_multi_instance "$app_id" "$new_uuid"
    
    # Mark safe mode as complete
    db_set_safe_mode_completed "$app_id"
    
    echo ""
    echo "✅ Safe mode validation complete for $display_name"
    echo ""
    
    debug_function_exit "$function_name" "Success"
    echo "$new_uuid"
    return 0
}
