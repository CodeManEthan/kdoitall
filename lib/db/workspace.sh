#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_WORKSPACE_LOADED" || return 0

db_create_workspace() {
    local workspace_name="$1"
    local description="$2"
    local function_name="db_create_workspace"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Execute INSERT
    db_query \
        "INSERT INTO workspace_definitions (
            workspace_name, description, is_active, created_at, last_opened_at
        ) VALUES (
            :workspace_name, :description, FALSE, datetime('now'), NULL
        );" \
        ":workspace_name" "$workspace_name" \
        ":description" "$description"
    
    if [[ "$DB_STATUS" != "OK" ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to create workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Created workspace: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}

db_delete_workspace() {
    local workspace_name="$1"
    local function_name="db_delete_workspace"
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    db_workspace_exists "$workspace_name" || return 1
    
    # Delete workspace
    db_query \
        "DELETE FROM workspace_definitions WHERE workspace_name = :workspace_name;
         SELECT changes();" \
        ":workspace_name" "$workspace_name"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Deleted workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete workspace: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_workspace_exists() {
    local workspace_name="$1"
    local function_name="db_workspace_exists"
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Check existence
    db_query \
        "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name = :workspace_name;" \
        ":workspace_name" "$workspace_name"
    
    if [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Workspace exists: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Workspace does not exist: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_workspace_not_exists() {
    local workspace_name="$1"
    local function_name="db_workspace_not_exists"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Check existence
    db_query \
        "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name = :workspace_name;" \
        ":workspace_name" "$workspace_name"
    
    if [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Workspace exists: $workspace_name"
        echo "Workspace name already exists." >&3
        debug_function_exit "$function_name"
        return 1
    else
        debug_log "$function_name" "Workspace does not exist: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    fi
}

db_list_workspaces() {
    local function_name="db_list_workspaces"
    
    debug_function_enter "$function_name"
    
    # Query all workspaces ordered by last opened (most recent first), then by creation
    db_query \
        "SELECT workspace_name, description, created_at, is_active, last_opened_at
         FROM workspace_definitions
         ORDER BY last_opened_at DESC NULLS LAST, created_at DESC;"
    
    # Note: Empty result is not an error - just means no workspaces defined
    debug_log "$function_name" "Listed workspaces"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_get_workspace() {
    local workspace_name="$1"
    local function_name="db_get_workspace"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Query workspace metadata
    db_query \
        "SELECT workspace_name, description, created_at, is_active, last_opened_at
         FROM workspace_definitions
         WHERE workspace_name = :workspace_name;" \
        ":workspace_name" "$workspace_name"
    
    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Retrieved workspace: $workspace_name"
    debug_function_exit "$function_name"
    printf '%s\n' "${DB_RESULT[@]}"
    return 0
}

db_set_workspace_last_opened() {
    local workspace_name="$1"
    local function_name="db_set_workspace_last_opened"
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Update timestamp
    db_query \
        "UPDATE workspace_definitions 
         SET last_opened_at = datetime('now')
         WHERE workspace_name = :workspace_name;
         SELECT changes();" \
        ":workspace_name" "$workspace_name"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Updated last_opened_at for: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_set_workspace_active() {
    local workspace_name="$1"
    local is_active="$2"
    local function_name="db_set_workspace_active"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$is_active" "is_active" || return 1
    
    is_active=$(normalize_boolean "$is_active")
    
    # Update is_active flag
    db_query \
        "UPDATE workspace_definitions 
         SET is_active = :is_active
         WHERE workspace_name = :workspace_name;
         SELECT changes();" \
        ":workspace_name" "$workspace_name" \
        ":is_active" "$is_active"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Set is_active=$is_active for: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_workspace_is_active() {
    local workspace_name="$1"
    local function_name="db_get_workspace_is_active"
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    db_query \
        "SELECT is_active 
         FROM workspace_definitions 
         WHERE workspace_name = :workspace_name;" \
        ":workspace_name" "$workspace_name"
    
    if [[ ${#DB_RESULT[@]} -eq 0 ]]; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Workspace '$workspace_name' is_active: ${DB_RESULT[0]}"
    debug_function_exit "$function_name"
    echo "${DB_RESULT[0]}"
    return 0
}

db_mark_workspace_opened() {
    local workspace_name="$1"
    local function_name="db_mark_workspace_opened"
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Set active and update timestamp in single connection
    db_query \
        "UPDATE workspace_definitions 
         SET is_active = TRUE, last_opened_at = datetime('now')
         WHERE workspace_name = :workspace_name;
         SELECT changes();" \
        ":workspace_name" "$workspace_name"
    
    if [[ "$DB_STATUS" == "OK" ]] && [[ "${DB_RESULT[0]:-0}" -eq 1 ]]; then
        debug_log "$function_name" "Marked workspace opened: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

db_get_workspace_window_details() {
    local workspace_name="$1"
    local function_name="db_get_workspace_window_details"

    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1

    db_query \
        "SELECT a.display_name, wd.app_id, wd.desktop, wd.screen, wd.position, wd.display_order
         FROM window_definitions wd
         LEFT JOIN applications a ON wd.app_id = a.app_id
         WHERE wd.workspace_name = :workspace_name
         ORDER BY wd.display_order;" \
        ":workspace_name" "$workspace_name"

    debug_log "$function_name" "Retrieved window details for workspace: $workspace_name"
    debug_function_exit "$function_name"
    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
    return 0
}