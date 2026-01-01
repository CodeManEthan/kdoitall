#!/bin/bash

check_and_set_guard "_KDOITALL_DB_WORKSPACE_LOADED" || return 0

# ============================================================================
# Workspace Database Functions
# ============================================================================
# These functions handle CRUD operations for workspace metadata
# Note: Database stores ONLY metadata - workspace configurations live in scripts

# ----------------------------------------------------------------------------
# db_create_workspace()
# Create new workspace metadata record
# Parameters:
#   $1 - workspace_name (required)
#   $2 - description (optional)
# Returns: 0 on success, 1 if workspace exists or on error
# ----------------------------------------------------------------------------
db_create_workspace() {
    local workspace_name="$1"
    local description="$2"
    local function_name="db_create_workspace"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate required parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Validate workspace name format
    if ! db_validate_workspace_name "$workspace_name"; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if workspace already exists
    if db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_EXISTS" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
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

# ----------------------------------------------------------------------------
# db_workspace_exists()
# Check if workspace exists in database
# Parameters:
#   $1 - workspace_name
# Returns: 0 if exists, 1 if not exists
# ----------------------------------------------------------------------------
db_workspace_exists() {
    local workspace_name="$1"
    local function_name="db_workspace_exists"
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
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

# ----------------------------------------------------------------------------
# db_list_workspaces()
# List all workspaces with metadata
# Returns: Multi-line output, one workspace per line:
#          workspace_name|description|created_at|is_active|last_opened_at
# ----------------------------------------------------------------------------
db_list_workspaces() {
    local function_name="db_list_workspaces"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
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

# ----------------------------------------------------------------------------
# db_get_workspace()
# Get complete workspace metadata
# Parameters:
#   $1 - workspace_name
# Returns: workspace_name|description|created_at|is_active|last_opened_at
# ----------------------------------------------------------------------------
db_get_workspace() {
    local workspace_name="$1"
    local function_name="db_get_workspace"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
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

# ----------------------------------------------------------------------------
# db_delete_workspace()
# Delete workspace record from database
# Parameters:
#   $1 - workspace_name
# Returns: 0 on success, 1 if workspace not found
# ----------------------------------------------------------------------------
db_delete_workspace() {
    local workspace_name="$1"
    local function_name="db_delete_workspace"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if exists before deleting
    if ! db_workspace_exists "$workspace_name"; then
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
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

# ----------------------------------------------------------------------------
# db_update_workspace_last_opened()
# Update last_opened_at timestamp to current time
# Parameters:
#   $1 - workspace_name
# Returns: 0 on success, 1 if workspace not found
# ----------------------------------------------------------------------------
db_update_workspace_last_opened() {
    local workspace_name="$1"
    local function_name="db_update_workspace_last_opened"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
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

# ----------------------------------------------------------------------------
# db_set_workspace_active()
# Set is_active flag for workspace
# Parameters:
#   $1 - workspace_name
#   $2 - is_active (TRUE or FALSE)
# Returns: 0 on success, 1 if workspace not found
# ----------------------------------------------------------------------------
db_set_workspace_active() {
    local workspace_name="$1"
    local is_active="$2"
    local function_name="db_set_workspace_active"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameters
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if [[ -z "$is_active" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "is_active"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Normalize boolean value to SQLite format
    local active_bool="FALSE"
    if [[ "$is_active" == "TRUE" || "$is_active" == "true" || "$is_active" == "1" ]]; then
        active_bool="TRUE"
    fi
    
    # Update is_active flag
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace_name '$workspace_name'" \
        -cmd ".param set :is_active '$active_bool'" \
        "UPDATE workspace_definitions 
         SET is_active = :is_active
         WHERE workspace_name = :workspace_name;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Set is_active=$active_bool for: $workspace_name"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_WORKSPACE_NOT_FOUND" "$workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# db_validate_workspace_name()
# Validate workspace name format
# Parameters:
#   $1 - workspace_name
# Returns: 0 if valid, 1 if invalid
# Rules:
#   - Not empty
#   - Max 50 characters
#   - Only alphanumeric, hyphens, and underscores
# ----------------------------------------------------------------------------
db_validate_workspace_name() {
    local workspace_name="$1"
    local function_name="db_validate_workspace_name"
    
    debug_function_enter "$function_name" "$@"
    
    # Check not empty
    if [[ -z "$workspace_name" ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Workspace name cannot be empty"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check length
    if [[ ${#workspace_name} -gt 50 ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Workspace name too long (max 50 characters): $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check format (alphanumeric, hyphens, underscores only)
    if ! [[ "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_WORKSPACE_NAME" "Invalid characters in workspace name: $workspace_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Workspace name is valid: $workspace_name"
    debug_function_exit "$function_name"
    return 0
}
