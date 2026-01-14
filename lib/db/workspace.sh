#!/bin/bash

check_and_set_guard "_KDOITALL_DB_WORKSPACE_LOADED" || return 0

db_create_workspace() {
    local workspace_name="$1"
    local description="$2"
    local function_name="db_create_workspace"
    
    debug_function_enter "$function_name" "$@"

    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Execute INSERT
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        -cmd ".param set :description '$description'" \
        "INSERT INTO workspace_definitions (
            workspace_name, description, is_active, created_at, last_opened_at
        ) VALUES (
            :workspace_name, :description, FALSE, datetime('now'), NULL
        );" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
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
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    db_workspace_exists "$workspace_name" || return 1
    
    # Delete workspace
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "DELETE FROM workspace_definitions WHERE workspace_name = :workspace_name;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
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
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Check existence
    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name = :workspace_name;" 2>/dev/null)
    
    if [[ "$count" -eq 1 ]]; then
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
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Check existence
    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name = :workspace_name;" 2>/dev/null)
    
    if [[ "$count" -eq 1 ]]; then
        debug_log "$function_name" "Workspace exists: $workspace_name"
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
    local result=""
    
    debug_function_enter "$function_name"
    
    # Query all workspaces ordered by last opened (most recent first), then by creation
    result=$(sqlite3 "$KDOITALL_DB" \
        "SELECT workspace_name, description, created_at, is_active, last_opened_at
         FROM workspace_definitions
         ORDER BY last_opened_at DESC NULLS LAST, created_at DESC;" 2>/dev/null)
    
    # Note: Empty result is not an error - just means no workspaces defined
    debug_log "$function_name" "Listed workspaces"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_get_workspace() {
    local workspace_name="$1"
    local function_name="db_get_workspace"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Query workspace metadata
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "SELECT workspace_name, description, created_at, is_active, last_opened_at
         FROM workspace_definitions
         WHERE workspace_name = :workspace_name;" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Retrieved workspace: $workspace_name"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

db_set_workspace_last_opened() {
    local workspace_name="$1"
    local function_name="db_set_workspace_last_opened"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    # Update timestamp
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "UPDATE workspace_definitions 
         SET last_opened_at = datetime('now')
         WHERE workspace_name = :workspace_name;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
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
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    validate_parameter_pass "$is_active" "is_active" || return 1
    
    is_active=$(normalize_boolean "$is_active")
    
    # Update is_active flag
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        -cmd ".param set :is_active '$is_active'" \
        "UPDATE workspace_definitions 
         SET is_active = :is_active
         WHERE workspace_name = :workspace_name;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
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
    local is_active=""
    
    debug_function_enter "$function_name" "$@"
    
    validate_parameter_pass "$workspace_name" "workspace_name" || return 1
    
    is_active=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        "SELECT is_active 
         FROM workspace_definitions 
         WHERE workspace_name = :workspace_name;" 2>/dev/null)
    
    if [[ -z "$is_active" ]]; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Workspace '$workspace_name' is_active: $is_active"
    debug_function_exit "$function_name"
    echo "$is_active"
    return 0
}
