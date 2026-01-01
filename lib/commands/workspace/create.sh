#!/bin/bash

# ============================================================================
# Workspace Create Command
# ============================================================================
# Interactive workspace creation with application configuration

check_and_set_guard "_KDOITALL_WORKSPACE_CREATE_LOADED" || return 0

# shellcheck source=../../db/workspace.sh
source "${LIB_DIR}/db/workspace.sh"

# ----------------------------------------------------------------------------
# workspace_create()
# Main function for interactive workspace creation
# Parameters:
#   $1 - workspace_name (required)
# ----------------------------------------------------------------------------
workspace_create() {
    local workspace_name="$1"
    local description=""
    local display_order=1
    local function_name="workspace_create"
    
    # Array to hold workspace configuration during creation
    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    declare -a WORKSPACE_APPS=()
    
    debug_function_enter "$function_name" "$@"
    
    # Validate workspace name provided
    if [[ -z "$workspace_name" ]]; then
        echo "Error: Workspace name required"
        echo "Usage: kdoitall workspace create <workspace-name>"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate workspace name format
    if ! db_validate_workspace_name "$workspace_name"; then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace exists
    if db_workspace_exists "$workspace_name"; then
        echo "Error: Workspace '$workspace_name' already exists"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Prompt for description
    echo ""
    echo "Creating workspace: $workspace_name"
    echo "Enter workspace description (optional, press Enter to skip):"
    read -r description
    
    # Note: We validate workspace doesn't exist, but don't create it yet
    # Database entry will be created at the end, after all apps are configured
    echo ""
    
    # Application addition loop
    while true; do
        echo "=== Add Application to Workspace ==="
        echo ""
        
        if ! add_application_to_workspace "$workspace_name" "$display_order" WORKSPACE_APPS; then
            echo "Error adding application. Try again? (y/n)"
            read -r retry
            if [[ "$retry" == "y" ]]; then
                continue
            else
                break
            fi
        fi
        
        ((display_order++))
        
        echo ""
        echo "Add another application? (y/n)"
        read -r continue_adding
        [[ "$continue_adding" != "y" ]] && break
    done
    
    # Check if any applications were added - must have at least one app
    if [[ ${#WORKSPACE_APPS[@]} -eq 0 ]]; then
        echo ""
        echo "Error: No applications added to workspace"
        echo "A workspace must have at least one application"
        echo "Workspace creation cancelled"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Final confirmation before committing to database
    echo ""
    echo "=== Workspace Configuration Summary ==="
    echo "Workspace: $workspace_name"
    echo "Description: ${description:-<none>}"
    echo "Applications configured: ${#WORKSPACE_APPS[@]}"
    echo ""
    echo "Proceed with workspace creation? (y/n)"
    read -r confirm_create
    
    if [[ "$confirm_create" != "y" ]]; then
        echo "Workspace creation cancelled"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Now create workspace in database (after user confirmation)
    echo ""
    echo "Creating workspace in database..."
    if ! db_create_workspace "$workspace_name" "$description"; then
        echo "Error: Failed to create workspace in database"
        debug_function_exit "$function_name"
        return 1
    fi
    echo "✓ Workspace created in database"
    
    # Generate scripts (passing the configuration array)
    echo ""
    echo "Generating workspace scripts..."
    
    # shellcheck source=generate.sh
    source "${LIB_DIR}/commands/workspace/generate.sh"
    
    if ! generate_workspace_scripts "$workspace_name" WORKSPACE_APPS; then
        echo "Error: Failed to generate workspace scripts"
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "✓ Scripts generated successfully"
    echo ""
    echo "================================================================"
    echo "Workspace '$workspace_name' created successfully!"
    echo "================================================================"
    echo ""
    echo "Open with:  kdoitall workspace open $workspace_name"
    echo "Close with: kdoitall workspace close $workspace_name"
    echo ""
    echo "Script files:"
    echo "  Open:  ${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-open.sh"
    echo "  Close: ${WORKSPACE_SCRIPTS_DIR}/${workspace_name}-close.sh"
    echo ""
    
    debug_function_exit "$function_name"
    return 0
}

# ----------------------------------------------------------------------------
# add_application_to_workspace()
# Interactive function to add a single application to workspace configuration
# Parameters:
#   $1 - workspace_name
#   $2 - display_order
#   $3 - reference to WORKSPACE_APPS array
# Returns: 0 on success, 1 on failure
# ----------------------------------------------------------------------------
add_application_to_workspace() {
    local workspace_name="$1"
    local display_order="$2"
    local -n apps_array_ref="$3"
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
    
    # Step 1: Select application
    echo "Step 1: Select Application"
    echo "--------------------------"
    if ! app_id=$(select_application); then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Step 2: Prompt for window name
    echo ""
    echo "Step 2: Window Name"
    echo "-------------------"
    echo "Enter a unique window name for this instance:"
    echo "  (alphanumeric, hyphens, and underscores only)"
    read -r window_name
    
    if [[ -z "$window_name" ]]; then
        echo "Error: Window name cannot be empty"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if ! validate_window_name "$window_name"; then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Step 3: Choose launch type (to determine launch function)
    echo ""
    echo "Step 3: Launch Type"
    echo "-------------------"
    if ! launch_type=$(choose_launch_type "$app_id"); then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Step 4: Determine launch function based on launch type
    if [[ "$launch_type" == "desktop" ]]; then
        # For desktop launches, use launch_by_app_id
        launch_function="launch_by_app_id"
    else
        # For terminal launches, user selects from app-specific launch options
        echo ""
        echo "Step 4: Launch Function"
        echo "-----------------------"
        if ! launch_function=$(select_launch_function "$app_id"); then
            debug_function_exit "$function_name"
            return 1
        fi
    fi
    
    # Step 5: Configure positioning
    echo ""
    echo "Step 5: Window Positioning"
    echo "--------------------------"
    if ! configure_positioning desktop_number screen_number position; then
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Step 6: Terminal-specific parameters
    if [[ "$launch_type" == "terminal" ]]; then
        # Prompt for parameters
        echo ""
        echo "Step 6: Function Parameters"
        echo "---------------------------"
        echo "Enter parameters for this function (space-separated):"
        echo "  Example: /path/to/project"
        echo "  (press Enter to skip if no parameters needed)"
        read -r parameters
    fi
    
    # Store in array for script generation
    # Format: app_id|window_name|launch_function|desktop|screen|position|parameters
    # Note: launch_type, launch_mode, and launch_command are NOT stored:
    #   - launch_type is only used during creation to determine the launch_function
    #   - launch_mode and launch_command are set internally by the launch functions
    apps_array_ref+=("$app_id|$window_name|$launch_function|$desktop_number|$screen_number|$position|$parameters")
    
    echo ""
    echo "✓ Added: $window_name ($app_id)"
    
    debug_function_exit "$function_name"
    return 0
}

# ----------------------------------------------------------------------------
# select_application()
# Interactive application selection from registry
# Returns: app_id on success, exits with error on failure
# ----------------------------------------------------------------------------
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
    echo "" >&2
    echo "Available Applications:" >&2
    echo "======================" >&2
    echo "" >&2
    
    local counter=1
    while IFS='|' read -r app_id display_name has_terminal has_desktop; do
        app_list+=("$app_id")
        
        local types=""
        [[ "$has_terminal" == "1" || "$has_terminal" == "TRUE" ]] && types+="T"
        [[ "$has_desktop" == "1" || "$has_desktop" == "TRUE" ]] && types+="D"
        
        printf "%3d) %-40s [%s]\n" "$counter" "$display_name" "$types" >&2
        ((counter++))
    done <<< "$apps"
    
    echo "" >&2
    echo "Legend: [T] = Terminal launch available, [D] = Desktop launch available" >&2
    echo "" >&2
    echo "Select application (1-$((counter-1))):" >&2
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

# ----------------------------------------------------------------------------
# choose_launch_type()
# Determine launch type based on application capabilities
# Parameters:
#   $1 - app_id
# Returns: "terminal" or "desktop"
# ----------------------------------------------------------------------------
choose_launch_type() {
    local app_id="$1"
    local app_info=""
    local has_terminal=""
    local has_desktop=""
    local function_name="choose_launch_type"
    
    debug_function_enter "$function_name" "$@"
    
    app_info=$(db_get_application "$app_id")
    has_terminal=$(echo "$app_info" | cut -d'|' -f7)
    has_desktop=$(echo "$app_info" | cut -d'|' -f8)
    
    # If only one type available, use it
    if [[ ("$has_terminal" == "1" || "$has_terminal" == "TRUE") && ("$has_desktop" == "0" || "$has_desktop" == "FALSE") ]]; then
        debug_log "$function_name" "Only terminal launch available"
        debug_function_exit "$function_name"
        echo "terminal"
        return 0
    elif [[ ("$has_desktop" == "1" || "$has_desktop" == "TRUE") && ("$has_terminal" == "0" || "$has_terminal" == "FALSE") ]]; then
        debug_log "$function_name" "Only desktop launch available"
        debug_function_exit "$function_name"
        echo "desktop"
        return 0
    fi
    
    # Both available, let user choose
    echo "This application supports both launch types:" >&2
    echo "  1) Desktop  - Simple GTK launch (uses .desktop file)" >&2
    echo "  2) Terminal - Advanced launch with custom options" >&2
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


# ----------------------------------------------------------------------------
# select_launch_function()
# Interactive selection of launch function for terminal launch
# Parameters:
#   $1 - app_id
# Returns: function_name on success
# ----------------------------------------------------------------------------
select_launch_function() {
    local app_id="$1"
    local options=""
    local option_list=()
    local function_name="select_launch_function"
    
    debug_function_enter "$function_name" "$@"
    
    options=$(db_get_launch_options "$app_id")
    
    if [[ -z "$options" ]]; then
        echo "Error: No launch options found for $app_id" >&2
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "" >&2
    echo "Available Launch Functions:" >&2
    echo "===========================" >&2
    echo "" >&2
    
    local counter=1
    while IFS='|' read -r function_name description; do
        option_list+=("$function_name")
        printf "%3d) %-40s\n" "$counter" "$function_name" >&2
        printf "     %s\n" "$description" >&2
        echo "" >&2
        ((counter++))
    done <<< "$options"
    
    echo "Select launch function (1-$((counter-1))):" >&2
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

# ----------------------------------------------------------------------------
# configure_positioning()
# Interactive configuration of window positioning
# Parameters (passed by reference):
#   $1 - desktop_ref
#   $2 - screen_ref
#   $3 - position_ref
# Returns: 0 on success, 1 on failure
# ----------------------------------------------------------------------------
configure_positioning() {
    local -n desktop_ref="$1"
    local -n screen_ref="$2"
    local -n position_ref="$3"
    local function_name="configure_positioning"
    
    debug_function_enter "$function_name" "$@"
    
    # Desktop selection
    echo "Detected virtual desktops: $DETECTED_DESKTOP_COUNT"
    echo "Enter desktop number (1-$DETECTED_DESKTOP_COUNT):"
    read -r desktop_ref
    
    if ! [[ "$desktop_ref" =~ ^[0-9]+$ ]] || \
       [ "$desktop_ref" -lt 1 ] || \
       [ "$desktop_ref" -gt "$DETECTED_DESKTOP_COUNT" ]; then
        echo "Error: Invalid desktop number"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Screen selection
    echo ""
    echo "Detected screens:"
    list_detected_screens
    echo ""
    echo "Enter screen number (1-$DETECTED_SCREEN_COUNT):"
    read -r screen_ref
    
    if ! [[ "$screen_ref" =~ ^[0-9]+$ ]] || \
       [ "$screen_ref" -lt 1 ] || \
       [ "$screen_ref" -gt "$DETECTED_SCREEN_COUNT" ]; then
        echo "Error: Invalid screen number"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Position selection
    echo ""
    echo "Available positions:"
    echo "  1) Fullscreen"
    echo "  2) Right Half"
    echo "  3) Left Half"
    echo "  4) Top Half"
    echo "  5) Bottom Half"
    echo "  6) Top Left"
    echo "  7) Top Right"
    echo "  8) Bottom Left"
    echo "  9) Bottom Right"
    echo " 10) Left Third"
    echo " 11) Middle Third"
    echo " 12) Right Third"
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
            echo "Error: Invalid choice"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    debug_log "$function_name" "Position configured: desktop=$desktop_ref, screen=$screen_ref, position=$position_ref"
    debug_function_exit "$function_name"
    return 0
}



