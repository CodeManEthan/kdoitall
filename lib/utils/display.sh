#!/bin/bash

check_and_set_guard "_KDOITALL_UTILS_DISPLAY_LOADED" || return 0

# ============================================================================
# Display Utility Functions
# ============================================================================
# Functions for formatted display of data to users

# Source required database functions
# shellcheck source=../db/window-info.sh
source "${LIB_DIR}/db/window-info.sh"

# ----------------------------------------------------------------------------
# display_tracked_windows()
# Display all windows currently tracked in the database with formatting
# Shows: UUID, Class, Window Title
# ----------------------------------------------------------------------------
display_tracked_windows() {
    local function_name="display_tracked_windows"
    local -a db_uuids
    local -a db_classes
    local -a db_titles
    
    debug_function_enter "$function_name"
    
    # Get data from database using proper functions
    mapfile -t db_uuids < <(db_get_existing_window_uuids)
    mapfile -t db_classes < <(db_get_existing_window_classes)
    mapfile -t db_titles < <(db_get_existing_window_titles)
    
    if [[ ${#db_uuids[@]} -eq 0 ]]; then
        echo "No windows currently tracked in database."
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Display header
    printf "%-19s %-30s %s\n" "UUID" "Class" "Window Title"
    echo "─────────────────── ────────────────────────────── ─────────────────────────────────"
    
    # Display each window
    local i
    for i in "${!db_uuids[@]}"; do
        printf "%-19s %-30s %s\n" \
            "${db_uuids[$i]}" \
            "${db_classes[$i]}" \
            "${db_titles[$i]}"
    done
    
    debug_function_exit "$function_name"
    return 0
}

# ----------------------------------------------------------------------------
# parse_window_title_segments()
# Parse window title into suggested patterns based on separators
# 
# This function splits window titles on " - " and " — " separators and
# generates suggestions for unique window title patterns. Suggestions
# include the separators to improve matching reliability.
# 
# Parameters:
#   $1 - title: The window title to parse
# 
# Returns: Newline-separated list of suggested patterns (rightmost first)
# 
# Example:
#   Input:  "Google Search — Mozilla Firefox"
#   Output: " — Mozilla Firefox"  (rightmost with left separator)
#           "Google Search — "    (leftmost with right separator)
# 
# Example with multiple separators:
#   Input:  "File - Project - VS Code"
#   Output: " - VS Code"           (rightmost)
#           " - Project - "        (middle with both)
#           "File - "              (leftmost)
# ----------------------------------------------------------------------------
parse_window_title_segments() {
    local title="$1"
    local function_name="parse_window_title_segments"
    local -a suggestions=()
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$title" ]]; then
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Strategy: Find all separators and build suggestions from right to left
    # We'll track positions of separators and build segments accordingly
    
    # First, let's find all separator positions using a different approach:
    # We'll process the string and find each occurrence of the separators
    
    local remaining="$title"
    local -a separator_positions=()  # Will store: "position|separator_text"
    local position=0
    
    # Find all separators (both types) and their positions
    while [[ -n "$remaining" ]]; do
        # Check for " — " first (the longer one should be checked first)
        if [[ "$remaining" =~ ^(.*?)(\ —\ )(.*) ]]; then
            local before="${BASH_REMATCH[1]}"
            local sep="${BASH_REMATCH[2]}"
            position=$((position + ${#before}))
            separator_positions+=("$position|$sep")
            position=$((position + ${#sep}))
            remaining="${BASH_REMATCH[3]}"
        elif [[ "$remaining" =~ ^(.*?)(\ -\ )(.*) ]]; then
            local before="${BASH_REMATCH[1]}"
            local sep="${BASH_REMATCH[2]}"
            position=$((position + ${#before}))
            separator_positions+=("$position|$sep")
            position=$((position + ${#sep}))
            remaining="${BASH_REMATCH[3]}"
        else
            # No more separators found
            break
        fi
    done
    
    # If no separators found, return empty
    if [[ ${#separator_positions[@]} -eq 0 ]]; then
        debug_log "$function_name" "No separators found in title"
        debug_function_exit "$function_name"
        return 0
    fi
    
    # Now build suggestions from the separators
    # For each separator, we want to suggest:
    # 1. Everything from that separator to the end (suffix with left separator)
    # 2. Everything from start to after that separator (prefix with right separator)
    
    local sep_count=${#separator_positions[@]}
    
    # Build suffix suggestions (rightmost first)
    for ((i = sep_count - 1; i >= 0; i--)); do
        local sep_info="${separator_positions[$i]}"
        local sep_pos="${sep_info%%|*}"
        local sep_text="${sep_info#*|}"
        
        # Extract from this separator to the end
        local suffix="${title:$sep_pos}"
        suggestions+=("$suffix")
    done
    
    # Build prefix suggestions (leftmost first, but we'll add them after suffixes)
    for ((i = 0; i < sep_count; i++)); do
        local sep_info="${separator_positions[$i]}"
        local sep_pos="${sep_info%%|*}"
        local sep_text="${sep_info#*|}"
        
        # Extract from start to after this separator
        local end_pos=$((sep_pos + ${#sep_text}))
        local prefix="${title:0:$end_pos}"
        
        # Only add if it's not already in suggestions (avoid duplicates)
        local already_exists=false
        for existing in "${suggestions[@]}"; do
            if [[ "$existing" == "$prefix" ]]; then
                already_exists=true
                break
            fi
        done
        
        if [[ "$already_exists" == "false" ]]; then
            suggestions+=("$prefix")
        fi
    done
    
    debug_log "$function_name" "Generated ${#suggestions[@]} suggestions"
    debug_function_exit "$function_name"
    
    # Return suggestions as newline-separated list
    printf '%s\n' "${suggestions[@]}"
    return 0
}
