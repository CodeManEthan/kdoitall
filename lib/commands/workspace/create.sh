#!/bin/bash

check_and_set_guard "_KDOITALL_WORKSPACE_CREATE_LOADED" || return 0

# shellcheck source=../../workspace/generator.sh
source "${LIB_DIR}/workspace/generator.sh"
# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"
# shellcheck source=../../db/app.sh
source "${LIB_DIR}/db/app.sh"
# shellcheck source=../../db/launch-options.sh
source "${LIB_DIR}/db/launch-options.sh"
# shellcheck source=../../utils/workspace-validators.sh
source "${LIB_DIR}/utils/workspace-validators.sh"

workspace_create() {
    local workspace_name="$1"
    local description=""
    local display_order=1
    local function_name="workspace_create"
    
    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()
    
    debug_function_enter "$function_name" "$@"
    
    validate_workspace_name "$workspace_name" || return 1
    db_workspace_not_exists "$workspace_name" || return 1

    # 1. Prompt for description
    echo "" >&3
    echo "Creating workspace: $workspace_name" >&3
    echo "Enter workspace description (optional, press Enter to skip):" >&3
    read -r description
    echo "" >&3
    
    # 2. Application addition loop
    while true; do
        echo "=== Add Application to Workspace ===" >&3
        echo "" >&3
        
        if ! add_application_to_workspace "$workspace_name" "$display_order" WORKSPACE_APPS; then
            echo "Error adding application. Try again? (y/n)" >&3
            read -r retry
            if [[ "$retry" == "y" ]]; then
                continue
            else
                break
            fi
        fi
        
        ((display_order++))
        
        echo "" >&3
        echo "Add another application? (y/n)" >&3
        read -r continue_adding
        [[ "$continue_adding" != "y" ]] && break
    done
    
    # Check if any applications were added - must have at least one app
    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_NO_APPLICATIONS" "Workspace creation cancelled"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Final confirmation before committing to database
    echo "" >&3
    echo "=== Workspace Configuration Summary ===" >&3
    echo "Workspace: $workspace_name" >&3
    echo "Description: ${description:-<none>}" >&3
    echo "Applications configured: ${#WORKSPACE_APPS[@]}" >&3
    echo "" >&3
    echo "Proceed with workspace creation? (y/n)" >&3
    read -r confirm_create
    
    if [[ "$confirm_create" != "y" ]]; then
        echo "Workspace creation cancelled" >&3
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Create workspace in database
    echo "" >&3
    echo "Creating workspace in database..." >&3
    if ! db_create_workspace "$workspace_name" "$description"; then
        debug_function_exit "$function_name"
        return 1
    fi
    echo "✓ Workspace created in database" >&3
    
    # Generate scripts (passing the configuration array)
    echo "" >&3
    echo "Generating workspace scripts..." >&3
    
    if ! generate_workspace_scripts "$workspace_name" WORKSPACE_APPS; then
        debug_error "$function_name" "$ERR_SCRIPT_GENERATION_FAILED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "✓ Scripts generated successfully" >&3
    echo "" >&3
    echo "================================================================" >&3
    echo "Workspace '$workspace_name' created successfully!" >&3
    echo "================================================================" >&3
    echo "" >&3
    echo "Open with:  kdoitall workspace open $workspace_name" >&3
    echo "Close with: kdoitall workspace close $workspace_name" >&3
    echo "" >&3
    echo "Script files:" >&3
    echo "  Open:  ${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh" >&3
    echo "  Close: ${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh" >&3
    echo "" >&3
    
    debug_function_exit "$function_name"
    return 0
}

add_application_to_workspace() {
    local workspace_name="$1"
    local display_order="$2"
    # apps_array_ref="$3"
    local app_id=""
    local window_name=""
    local launch_type=""
    local launch_function=""
    local desktop_number=""
    local screen_number=""
    local position=""
    local parameters=""
    local function_name="add_application_to_workspace"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$3" "apps_array_ref" || return 1
    local -n apps_array_ref="$3"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$display_order" "display_order" || return 1
    
    # Step 1: Select application
    echo "Step 1: Select Application" >&3
    echo "--------------------------" >&3
    if ! app_id=$(select_application); then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Get the display name for the selected app
    local display_name=""
    display_name=$(db_get_display_name "$app_id")

    # Count existing instances of this app_id in the workspace
    local instance_count=1
    for app_entry in "${apps_array_ref[@]}"; do
        local existing_app_id=""
        existing_app_id=$(echo "$app_entry" | cut -d'|' -f1)
        
        if [[ "$existing_app_id" == "$app_id" ]]; then
            ((instance_count++))
        fi
    done

    # Sanitize display name:
    local sanitized_display_name=""
    sanitized_display_name=$(echo "$display_name" | \
        tr '[:upper:]' '[:lower:]' | \
        tr ' _' '-' | \
        sed 's/[^a-z0-9-]//g' | \
        sed 's/--*/-/g')

    # Generate window name automatically
    window_name="${workspace_name}-${sanitized_display_name}-${instance_count}"
    
    validate_window_name "$window_name" || return 1
    
    # Step 2: Choose launch type (to determine launch function)
    echo "" >&3
    echo "Step 2: Launch Type" >&3
    echo "-------------------" >&3
    if ! launch_type=$(choose_launch_type "$app_id"); then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Step 3: Configure positioning
    echo "" >&3
    echo "Step 3: Window Positioning" >&3
    echo "--------------------------" >&3
    if ! configure_positioning desktop_number screen_number position; then
        debug_function_exit "$function_name"
        return 1
    fi

    # Step 4: Determine launch function based on launch type
    if [[ "$launch_type" == "$LAUNCH_TYPE_DESKTOP" ]]; then
        # For desktop launches, use launch_by_app_id
        launch_function="launch_by_app_id"
    else
        # For terminal launches, user selects from app-specific launch options
        echo "" >&3
        echo "Step 4: Launch Function" >&3
        echo "-----------------------" >&3
        if ! launch_function=$(select_launch_function "$app_id"); then
            debug_function_exit "$function_name"
            return 1
        fi
    fi
    
    # Step 5: Terminal-specific parameters
    if [[ "$launch_type" == "$LAUNCH_TYPE_TERMINAL" ]]; then
        # Prompt for parameters
        echo "" >&3
        echo "Step 5: Function Parameters" >&3
        echo "---------------------------" >&3
        echo "Enter parameters for this function (space-separated):" >&3
        echo "  Example: /path/to/project" >&3
        echo "  (press Enter to skip if no parameters needed)" >&3
        read -r parameters
    fi
    
    # Store in array for script generation
    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    apps_array_ref+=("$app_id|$window_name|$launch_function|$desktop_number|$screen_number|$position|$parameters")
    
    echo "" >&3
    echo "✓ Added: $window_name ($app_id)" >&3
    
    debug_function_exit "$function_name"
    return 0
}

select_application() {
    local apps=""
    local app_list=()
    local selection=""
    local function_name="select_application"
    
    debug_function_enter "$function_name"
    
    # Get all applications
    apps=$(db_list_applications "all")
    
    if [[ -z "$apps" ]]; then
        echo "Error: No applications found in registry" >&2
        echo "Run 'kdoitall scan' to populate the registry" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Display applications
    echo "" >&3
    echo "Available Applications:" >&3
    echo "======================" >&3
    echo "" >&3
    
    local counter=1
    while IFS='|' read -r app_id display_name has_terminal has_desktop; do
        app_list+=("$app_id")
        
        local types=""
        [[ "$has_terminal" == "1" || "$has_terminal" == "TRUE" ]] && types+="T"
        [[ "$has_desktop" == "1" || "$has_desktop" == "TRUE" ]] && types+="D"
        
        printf "%3d) %-40s [%s]\n" "$counter" "$display_name" "$types" >&3
        ((counter++))
    done <<< "$apps"
    
    echo "" >&3
    echo "Legend: [T] = Terminal launch available, [D] = Desktop launch available" >&3
    echo "" >&3
    echo "Select application (1-$((counter-1))):" >&3
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [ "$selection" -lt 1 ] || \
       [ "$selection" -ge "$counter" ]; then
        echo "Error: Invalid selection" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    local selected_app_id="${app_list[$((selection-1))]}"
    debug_log "$function_name" "Selected: $selected_app_id"
    debug_function_exit "$function_name"
    echo "$selected_app_id"
}

choose_launch_type() {
    local app_id="$1"
    local app_info=""
    local has_terminal_launch=""
    local has_desktop_launch=""
    local function_name="choose_launch_type"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    app_info=$(db_get_application "$app_id")
    has_terminal_launch=$(echo "$app_info" | cut -d'|' -f7)
    has_desktop_launch=$(echo "$app_info" | cut -d'|' -f8)
    
    # If only one type available, use it
    if [[ ("$has_terminal_launch" == "1" || "$has_terminal_launch" == "TRUE") && ("$has_desktop_launch" == "0" || "$has_desktop_launch" == "FALSE") ]]; then
        debug_log "$function_name" "Only terminal launch available"
        debug_function_exit "$function_name"
        echo "$LAUNCH_TYPE_TERMINAL"
        return 0
    elif [[ ("$has_desktop_launch" == "1" || "$has_desktop_launch" == "TRUE") && ("$has_terminal_launch" == "0" || "$has_terminal_launch" == "FALSE") ]]; then
        debug_log "$function_name" "Only desktop launch available"
        debug_function_exit "$function_name"
        echo "$LAUNCH_TYPE_DESKTOP"
        return 0
    fi
    
    echo "This application supports both launch types:" >&3
    echo "  1) Desktop  - Simple GTK launch (uses .desktop file)" >&3
    echo "  2) Terminal - Advanced launch with custom options" >&3
    read -r type_choice
    
    case "$type_choice" in
        1) 
            debug_log "$function_name" "User selected desktop launch"
            debug_function_exit "$function_name"
            echo "desktop"
            ;;
        2) 
            debug_log "$function_name" "User selected terminal launch"
            debug_function_exit "$function_name"
            echo "terminal"
            ;;
        *) 
            echo "Error: Invalid choice" >&2
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
}

select_launch_function() {
    local app_id="$1"
    local options=""
    local option_list=()
    local function_name="select_launch_function"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$app_id" "app_id" || return 1
    
    options=$(db_get_launch_options "$app_id")
    
    if [[ -z "$options" ]]; then
        echo "Error: No launch options found for $app_id" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "" >&3
    echo "Available Launch Functions:" >&3
    echo "===========================" >&3
    echo "" >&3
    
    local counter=1
    while IFS='|' read -r function_name description; do
        option_list+=("$function_name")
        printf "%3d) %-40s\n" "$counter" "$function_name" >&3
        printf "     %s\n" "$description" >&3
        echo "" >&3
        ((counter++))
    done <<< "$options"
    
    echo "Select launch function (1-$((counter-1))):" >&3
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || \
       [ "$selection" -lt 1 ] || \
       [ "$selection" -ge "$counter" ]; then
        echo "Error: Invalid selection" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    local selected_function="${option_list[$((selection-1))]}"
    debug_log "$function_name" "Selected: $selected_function"
    debug_function_exit "$function_name"
    echo "$selected_function"
}

configure_positioning() {
    # desktop_ref="$1"
    # screen_ref="$2"
    # position_ref="$3"
    local function_name="configure_positioning"

    validate_parameter_pass "$1" "desktop_ref" || return 1
    validate_parameter_pass "$2" "screen_ref" || return 1
    validate_parameter_pass "$3" "position_ref" || return 1
    local -n desktop_ref="$1"
    local -n screen_ref="$2"
    local -n position_ref="$3"
    
    debug_function_enter "$function_name" "$@"
    
    # Desktop selection
    echo "Detected virtual desktops: $DETECTED_DESKTOP_COUNT" >&3
    echo "Enter desktop number (1-$DETECTED_DESKTOP_COUNT):" >&3
    read -r desktop_ref
    
    if ! [[ "$desktop_ref" =~ ^[0-9]+$ ]] || \
       [ "$desktop_ref" -lt 1 ] || \
       [ "$desktop_ref" -gt "$DETECTED_DESKTOP_COUNT" ]; then
        echo "Error: Invalid desktop number" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Screen selection
    echo "" >&3
    echo "Detected screens:" >&3
    list_detected_screens
    echo "" >&3
    echo "Enter screen number (1-$DETECTED_SCREEN_COUNT):" >&3
    read -r screen_ref
    
    if ! [[ "$screen_ref" =~ ^[0-9]+$ ]] || \
       [ "$screen_ref" -lt 1 ] || \
       [ "$screen_ref" -gt "$DETECTED_SCREEN_COUNT" ]; then
        echo "Error: Invalid screen number" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Position selection
    echo "" >&3
    echo "Available positions:" >&3
    echo "  1) Fullscreen" >&3
    echo "  2) Right Half" >&3
    echo "  3) Left Half" >&3
    echo "  4) Top Half" >&3
    echo "  5) Bottom Half" >&3
    echo "  6) Top Left" >&3
    echo "  7) Top Right" >&3
    echo "  8) Bottom Left" >&3
    echo "  9) Bottom Right" >&3
    echo " 10) Left Third" >&3
    echo " 11) Middle Third" >&3
    echo " 12) Right Third" >&3
    read -r pos_choice
    
    case "$pos_choice" in
        1) position_ref="FULLSCREEN" ;;
        2) position_ref="RIGHTHALF" ;;
        3) position_ref="LEFTHALF" ;;
        4) position_ref="TOPHALF" ;;
        5) position_ref="BOTTOMHALF" ;;
        6) position_ref="TOPLEFT" ;;
        7) position_ref="TOPRIGHT" ;;
        8) position_ref="BOTTOMLEFT" ;;
        9) position_ref="BOTTOMRIGHT" ;;
        10) position_ref="LEFTTHIRD" ;;
        11) position_ref="MIDDLETHIRD" ;;
        12) position_ref="RIGHTTHIRD" ;;
        *) 
            echo "Error: Invalid choice" >&2
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    debug_log "$function_name" "Position configured: desktop=$desktop_ref, screen=$screen_ref, position=$position_ref"
    debug_function_exit "$function_name"
    return 0
}



