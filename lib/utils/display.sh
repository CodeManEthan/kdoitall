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
