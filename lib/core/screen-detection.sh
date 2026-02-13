#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_and_set_guard "_KDOITALL_SCREEN_DETECTION_LOADED" || return 0

# Global variable to store detected desktop count
declare -g DETECTED_DESKTOP_COUNT=0
# Global associative array to store screen information
declare -g -A SCREEN_INFO
declare -g DETECTED_SCREEN_COUNT=0

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

detect_screens() {
    local function_name="detect_screens"
    local kscreen_json=""
    
    debug_function_enter "$function_name"
    
    # Get kscreen-doctor JSON output
    kscreen_json=$(kscreen-doctor --json 2>/dev/null)
    
    if [[ -z "$kscreen_json" ]]; then
        debug_error "$function_name" "$ERR_KSCREEN_DETECTION_FAILED" "No output from kscreen-doctor --json"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Clear existing screen info
    SCREEN_INFO=()
    DETECTED_SCREEN_COUNT=0
    
    # Parse JSON and extract enabled outputs
    local output_count
    output_count=$(echo "$kscreen_json" | jq -r '.outputs | length')
    
    for ((i=0; i<output_count; i++)); do
        local output_id
        local output_name
        local output_enabled
        local pos_x
        local pos_y
        local width
        local height
        
        # Extract values using jq
        output_id=$(echo "$kscreen_json" | jq -r ".outputs[$i].id")
        output_name=$(echo "$kscreen_json" | jq -r ".outputs[$i].name")
        output_enabled=$(echo "$kscreen_json" | jq -r ".outputs[$i].enabled")
        pos_x=$(echo "$kscreen_json" | jq -r ".outputs[$i].pos.x")
        pos_y=$(echo "$kscreen_json" | jq -r ".outputs[$i].pos.y")
        width=$(echo "$kscreen_json" | jq -r ".outputs[$i].size.width")
        height=$(echo "$kscreen_json" | jq -r ".outputs[$i].size.height")
        
        # Store in SCREEN_INFO array
        SCREEN_INFO["${output_id}_NAME"]="$output_name"
        SCREEN_INFO["${output_id}_ENABLED"]="$output_enabled"
        SCREEN_INFO["${output_id}_X"]="$pos_x"
        SCREEN_INFO["${output_id}_Y"]="$pos_y"
        SCREEN_INFO["${output_id}_WIDTH"]="$width"
        SCREEN_INFO["${output_id}_HEIGHT"]="$height"
        
        debug_log "$function_name" "Found Output $output_id: $output_name (enabled: $output_enabled)"
        
        if [[ "$output_enabled" == "true" ]]; then
            ((DETECTED_SCREEN_COUNT++))
            debug_log "$function_name" "Output $output_id geometry: ${width}x${height} at ($pos_x,$pos_y)"
        fi
    done
    
    # Validate we found at least one enabled screen
    if [[ $DETECTED_SCREEN_COUNT -eq 0 ]]; then
        debug_error "$function_name" "$ERR_NO_SCREENS_DETECTED"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Detected $DETECTED_SCREEN_COUNT enabled screen(s)"
    
    debug_function_exit "$function_name"
    return 0
}

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

list_detected_screens() {
    local function_name="list_detected_screens"
    local out=""
    
    debug_function_enter "$function_name"
    
    if [[ $DETECTED_SCREEN_COUNT -eq 0 ]]; then
        debug_log "$function_name" "No screens detected. Run detect_screens() first."
        debug_function_exit "$function_name"
        return 1
    fi
    
    echo "Detected Screens: $DETECTED_SCREEN_COUNT" >&3
    echo "----------------------------------------" >&3
    
    for ((out=1; out<=20; out++)); do
        # Check if this output exists before trying to access its ENABLED status
        if [[ -n "${SCREEN_INFO[${out}_ENABLED]:-}" && "${SCREEN_INFO[${out}_ENABLED]}" == "true" ]]; then
            local name="${SCREEN_INFO[${out}_NAME]}"
            local width="${SCREEN_INFO[${out}_WIDTH]}"
            local height="${SCREEN_INFO[${out}_HEIGHT]}"
            local x="${SCREEN_INFO[${out}_X]}"
            local y="${SCREEN_INFO[${out}_Y]}"
            
            echo "Output $out: $name" >&3
            echo "  Resolution: ${width}x${height}" >&3
            echo "  Position: ($x, $y)" >&3
        fi
    done
    
    debug_function_exit "$function_name"
}

get_screen_info() {
    local output_num="$1"
    local property="$2"
    local key="${output_num}_${property}"
    local value="${SCREEN_INFO[$key]}"
    
    # Properties: NAME, UUID, ENABLED, X, Y, WIDTH, HEIGHT
    echo "$value"
}

resolve_screen_reference() {
    local screen_ref="$1"
    local function_name="resolve_screen_reference"
    local out=""
    
    debug_function_enter "$function_name" "$@"

    # Resolve a screen reference to an output number
    # Supports three tiers:
    #   1. Direct output numbers (1, 2, 3...)
    #   2. Screen names (eDP-1, HDMI-A-1, DP-1, etc.)
    #   3. User-defined aliases (primary, laptop, vertical, etc.)
    # Returns: output number on success, empty on failure
    
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



