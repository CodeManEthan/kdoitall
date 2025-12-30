#!/bin/bash

# Sources:
# core/common.sh
# core/error_codes.sh

check_and_set_guard "_KDOITALL_SCREEN_DETECTION_LOADED" || return 0

# Global variable to store detected desktop count
declare -g DETECTED_DESKTOP_COUNT=0
# Global associative array to store screen information
declare -g -A SCREEN_INFO
declare -g DETECTED_SCREEN_COUNT=0

# Detect the number of virtual desktops from kdotool
# Returns: 0 on success, 1 on failure
detect_desktops() {
    local function_name="detect_desktops"
    local desktop_count=""
    
    debug_function_enter "$function_name"
    
    # Get desktop count from kdotool
    desktop_count=$(kdotool get_num_desktops 2>/dev/null)
    
    if [[ -z "$desktop_count" ]]; then
        debug_error "$function_name" "$ERR_KDOTOOL_DESKTOP_DETECTION_FAILED" "No output from kdotool get_num_desktops"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate it's a number
    if ! [[ "$desktop_count" =~ ^[0-9]+$ ]]; then
        debug_error "$function_name" "$ERR_KDOTOOL_DESKTOP_DETECTION_FAILED" "Invalid output: $desktop_count"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate at least 1 desktop exists
    if [[ "$desktop_count" -lt 1 ]]; then
        debug_error "$function_name" "$ERR_NO_DESKTOPS_DETECTED" "Desktop count: $desktop_count"
        debug_function_exit "$function_name"
        return 1
    fi
    
    DETECTED_DESKTOP_COUNT="$desktop_count"
    
    debug_log "$function_name" "Detected $DETECTED_DESKTOP_COUNT virtual desktop(s)"
    debug_function_exit "$function_name"
    return 0
}

# Detect and parse screen configuration from kscreen-doctor
# Populates SCREEN_INFO associative array with screen data
# Returns: 0 on success, 1 on failure
detect_screens() {
    local function_name="detect_screens"
    local kscreen_output=""
    local current_output_num=0
    local line=""
    
    debug_function_enter "$function_name"
    
    # Get kscreen-doctor output
    kscreen_output=$(kscreen-doctor -o 2>/dev/null)
    
    if [[ -z "$kscreen_output" ]]; then
        debug_error "$function_name" "$ERR_KSCREEN_DETECTION_FAILED" "No output from kscreen-doctor"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Clear existing screen info
    SCREEN_INFO=()
    DETECTED_SCREEN_COUNT=0
    
    # Parse output line by line
    while IFS= read -r line; do
        # Detect new output (starts with "Output: ")
        # Example: "Output: 1 eDP-1 d0a34112-3c2f-4d4a-97fc-03a893f1e8da"
        if [[ "$line" =~ ^Output:[[:space:]]+([0-9]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
            current_output_num="${BASH_REMATCH[1]}"
            SCREEN_INFO["${current_output_num}_NAME"]="${BASH_REMATCH[2]}"
            SCREEN_INFO["${current_output_num}_UUID"]="${BASH_REMATCH[3]}"
            debug_log "$function_name" "Found Output $current_output_num: ${BASH_REMATCH[2]}"
            continue
        fi
        
        # Skip if we haven't found an output yet
        [[ $current_output_num -eq 0 ]] && continue
        
        # Parse enabled status
        if [[ "$line" =~ ^[[:space:]]*enabled[[:space:]]*$ ]]; then
            SCREEN_INFO["${current_output_num}_ENABLED"]="true"
            ((DETECTED_SCREEN_COUNT++))
            debug_log "$function_name" "Output $current_output_num is enabled"
            continue
        fi
        
        # Parse disabled status
        if [[ "$line" =~ ^[[:space:]]*disabled[[:space:]]*$ ]]; then
            SCREEN_INFO["${current_output_num}_ENABLED"]="false"
            debug_log "$function_name" "Output $current_output_num is disabled"
            continue
        fi
        
        # Parse geometry: "Geometry: X,Y WIDTHxHEIGHT"
        # Example: "Geometry: 1920,0 1920x1080"
        if [[ "$line" =~ Geometry:[[:space:]]*([0-9]+),([0-9]+)[[:space:]]+([0-9]+)x([0-9]+) ]]; then
            SCREEN_INFO["${current_output_num}_X"]="${BASH_REMATCH[1]}"
            SCREEN_INFO["${current_output_num}_Y"]="${BASH_REMATCH[2]}"
            SCREEN_INFO["${current_output_num}_WIDTH"]="${BASH_REMATCH[3]}"
            SCREEN_INFO["${current_output_num}_HEIGHT"]="${BASH_REMATCH[4]}"
            
            debug_log "$function_name" "Output $current_output_num geometry: ${BASH_REMATCH[3]}x${BASH_REMATCH[4]} at (${BASH_REMATCH[1]},${BASH_REMATCH[2]})"
            continue
        fi
        
    done <<< "$kscreen_output"
    
    # Validate we found at least one enabled screen
    if [[ $DETECTED_SCREEN_COUNT -eq 0 ]]; then
        debug_error "$function_name" "$ERR_NO_SCREENS_DETECTED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Detected $DETECTED_SCREEN_COUNT enabled screen(s)"
    
    # Update NUM_SCREENS to match detected count
    export NUM_SCREENS="$DETECTED_SCREEN_COUNT"
    
    debug_function_exit "$function_name"
    return 0
}

# Get screen information by output number and property
# Usage: get_screen_info OUTPUT_NUM PROPERTY
# Properties: NAME, UUID, ENABLED, X, Y, WIDTH, HEIGHT
# Returns: property value or empty string if not found
get_screen_info() {
    local output_num="$1"
    local property="$2"
    local key="${output_num}_${property}"
    local value="${SCREEN_INFO[$key]}"
    
    echo "$value"
}

# Resolve a screen reference to an output number
# Supports three tiers:
#   1. Direct output numbers (1, 2, 3...)
#   2. Screen names (eDP-1, HDMI-A-1, DP-1, etc.)
#   3. User-defined aliases (primary, laptop, vertical, etc.)
# Returns: output number on success, empty on failure
resolve_screen_reference() {
    local screen_ref="$1"
    local function_name="resolve_screen_reference"
    local out=""
    
    debug_function_enter "$function_name" "$@"
    
    # Tier 1: Check if it's a direct output number
    if [[ "$screen_ref" =~ ^[0-9]+$ ]]; then
        if [[ "${SCREEN_INFO[${screen_ref}_ENABLED]}" == "true" ]]; then
            debug_log "$function_name" "Tier 1: Direct output number: $screen_ref"
            debug_function_exit "$function_name"
            echo "$screen_ref"
            return 0
        else
            debug_error "$function_name" "$ERR_SCREEN_DISABLED_OR_NOT_FOUND" "Output $screen_ref"
            debug_function_exit "$function_name"
            return 1
        fi
    fi
    
    # Tier 2: Check if it's a screen name (eDP-1, HDMI-A-1, etc.)
    for ((out=1; out<=20; out++)); do
        if [[ "${SCREEN_INFO[${out}_NAME]}" == "$screen_ref" && "${SCREEN_INFO[${out}_ENABLED]}" == "true" ]]; then
            debug_log "$function_name" "Tier 2: Resolved name '$screen_ref' to output $out"
            debug_function_exit "$function_name"
            echo "$out"
            return 0
        fi
    done
    
    # Tier 3: Check if it's an alias (load from config file)
    local alias_file="${KDOITALL_CONFIG}/screen-aliases"
    if [[ -f "$alias_file" ]]; then
        local alias_target=""
        alias_target=$(grep "^${screen_ref}=" "$alias_file" 2>/dev/null | cut -d= -f2)
        
        if [[ -n "$alias_target" ]]; then
            debug_log "$function_name" "Tier 3: Found alias '$screen_ref' -> '$alias_target'"
            # Recursively resolve in case alias points to another alias or name
            local resolved=""
            resolved=$(resolve_screen_reference "$alias_target")
            if [[ -n "$resolved" ]]; then
                debug_function_exit "$function_name"
                echo "$resolved"
                return 0
            fi
        fi
    fi
    
    debug_error "$function_name" "$ERR_SCREEN_REFERENCE_NOT_FOUND" "Cannot resolve '$screen_ref'"
    debug_function_exit "$function_name"
    return 1
}

# Refresh screen configuration (useful after monitor hotplug)
# Returns: 0 on success, 1 on failure
refresh_screens() {
    local function_name="refresh_screens"
    
    debug_function_enter "$function_name"
    
    if detect_screens; then
        debug_log "$function_name" "Screen configuration refreshed: $DETECTED_SCREEN_COUNT screens"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_SCREEN_REFRESH_FAILED"
        debug_function_exit "$function_name"
        return 1
    fi
}

# List all detected screens with their properties
# Useful for debugging and user information
list_detected_screens() {
    local function_name="list_detected_screens"
    local out=""
    
    debug_function_enter "$function_name"
    
    if [[ $DETECTED_SCREEN_COUNT -eq 0 ]]; then
        debug_log "$function_name" "No screens detected. Run detect_screens() first."
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "Detected Screens: $DETECTED_SCREEN_COUNT"
    echo "----------------------------------------"
    
    for ((out=1; out<=20; out++)); do
        if [[ "${SCREEN_INFO[${out}_ENABLED]}" == "true" ]]; then
            local name="${SCREEN_INFO[${out}_NAME]}"
            local width="${SCREEN_INFO[${out}_WIDTH]}"
            local height="${SCREEN_INFO[${out}_HEIGHT]}"
            local x="${SCREEN_INFO[${out}_X]}"
            local y="${SCREEN_INFO[${out}_Y]}"
            
            echo "Output $out: $name"
            echo "  Resolution: ${width}x${height}"
            echo "  Position: ($x, $y)"
        fi
    done
    
    debug_function_exit "$function_name"
}