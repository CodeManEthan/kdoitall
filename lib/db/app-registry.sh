#!/bin/bash

check_and_set_guard "_KDOITALL_DB_APP_REGISTRY_LOADED" || return 0


# ============================================================================
# Application Registry Database Functions
# ============================================================================
# These functions handle CRUD operations for the application registry tables

# ----------------------------------------------------------------------------
# db_add_application()
# Insert or update an application in the database with all metadata
# ----------------------------------------------------------------------------
db_add_application() {
    local app_id="$1"
    local display_name="$2"
    local desktop_file_path="$3"
    local app_file_path="$4"
    local terminal_command="$5"
    local app_class="$6"
    local has_terminal_launch="$7"
    local has_desktop_launch="$8"
    local function_name="db_add_application"
    
    debug_function_enter "$function_name" "$@"
    
    # Validate required parameters
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if [[ -z "$display_name" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "display_name"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Convert boolean strings to SQLite format (TRUE/FALSE)
    local terminal_bool="FALSE"
    [[ "$has_terminal_launch" == "true" || "$has_terminal_launch" == "TRUE" || "$has_terminal_launch" == "1" ]] && terminal_bool="TRUE"
    
    local desktop_bool="FALSE"
    [[ "$has_desktop_launch" == "true" || "$has_desktop_launch" == "TRUE" || "$has_desktop_launch" == "1" ]] && desktop_bool="TRUE"
    
    # Execute INSERT OR REPLACE
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :display_name '$display_name'" \
        -cmd ".param set :desktop_file '$desktop_file_path'" \
        -cmd ".param set :app_file '$app_file_path'" \
        -cmd ".param set :terminal_cmd '$terminal_command'" \
        -cmd ".param set :app_class '$app_class'" \
        -cmd ".param set :has_terminal '$terminal_bool'" \
        -cmd ".param set :has_desktop '$desktop_bool'" \
        "INSERT OR REPLACE INTO applications (
            app_id, display_name, desktop_file_path,
            app_file_path, terminal_command, app_class,
            has_terminal_launch, has_desktop_launch,
            last_validated
        ) VALUES (
            :app_id, :display_name, :desktop_file,
            :app_file, :terminal_cmd, :app_class,
            :has_terminal, :has_desktop,
            datetime('now')
        );" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to add application: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Added/updated application: $app_id ($display_name)"
    debug_function_exit "$function_name"
    return 0
}

# ----------------------------------------------------------------------------
# db_get_application()
# Retrieve complete information for a single application
# Returns: app_id|display_name|desktop_file_path|app_file_path|terminal_command|app_class|has_terminal_launch|has_desktop_launch|last_validated
# ----------------------------------------------------------------------------
db_get_application() {
    local app_id="$1"
    local function_name="db_get_application"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Query database with all fields
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_id, display_name, desktop_file_path,
                app_file_path, terminal_command, app_class,
                has_terminal_launch, has_desktop_launch,
                last_validated
         FROM applications
         WHERE app_id = :app_id;" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    debug_log "$function_name" "Retrieved application: $app_id"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_list_applications()
# List applications with optional filtering
# Parameters: filter = "all", "terminal", "desktop", "both" (default: "all")
# Returns: Multi-line output, one app per line:
#          app_id|display_name|has_terminal_launch|has_desktop_launch
# ----------------------------------------------------------------------------
db_list_applications() {
    local filter="${1:-all}"
    local function_name="db_list_applications"
    local query=""
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    # Build query based on filter
    case "$filter" in
        all)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   ORDER BY display_name;"
            ;;
        terminal)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_terminal_launch = TRUE
                   ORDER BY display_name;"
            ;;
        desktop)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_desktop_launch = TRUE
                   ORDER BY display_name;"
            ;;
        both)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch
                   FROM applications
                   WHERE has_terminal_launch = TRUE AND has_desktop_launch = TRUE
                   ORDER BY display_name;"
            ;;
        *)
            debug_error "$function_name" "$ERR_INVALID_PARAMETER" "Invalid filter: $filter"
            debug_function_exit "$function_name"
            return 1
            ;;
    esac
    
    # Execute query
    result=$(sqlite3 "$KDOITALL_DB" "$query" 2>/dev/null)
    
    # Note: Empty result is not an error - just means no apps match filter
    debug_log "$function_name" "Listed applications with filter: $filter"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_application_exists()
# Check if an application exists in the database
# Returns: 0 if exists, 1 if not exists
# ----------------------------------------------------------------------------
db_application_exists() {
    local app_id="$1"
    local function_name="db_application_exists"
    local count=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check existence
    count=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT COUNT(*) FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    if [[ "$count" -eq 1 ]]; then
        debug_log "$function_name" "Application exists: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_log "$function_name" "Application does not exist: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# db_delete_application()
# Remove an application from the database
# Returns: 0 on success, 1 if app_id not found
# ----------------------------------------------------------------------------
db_delete_application() {
    local app_id="$1"
    local function_name="db_delete_application"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Check if exists before deleting
    if ! db_application_exists "$app_id"; then
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Delete application
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "DELETE FROM applications WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Deleted application: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_DATABASE_ERROR" "Failed to delete application: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# db_update_validation_timestamp()
# Update the last_validated timestamp for an application
# Returns: 0 on success, 1 if app_id not found
# ----------------------------------------------------------------------------
db_update_validation_timestamp() {
    local app_id="$1"
    local function_name="db_update_validation_timestamp"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Update timestamp
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "UPDATE applications 
         SET last_validated = datetime('now')
         WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Updated validation timestamp for: $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# db_get_applications_needing_validation()
# Find applications that haven't been validated recently
# Parameters: days = number of days (optional, default: 7)
# Returns: List of app_ids that need validation (one per line)
# ----------------------------------------------------------------------------
db_get_applications_needing_validation() {
    local days="${1:-7}"
    local function_name="db_get_applications_needing_validation"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    # Validate parameter is a number
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        debug_error "$function_name" "$ERR_INVALID_PARAMETER" "days must be a number: $days"
        debug_function_exit "$function_name"
        return 1
    fi
    
    # Query applications needing validation
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :days '$days'" \
        "SELECT app_id
         FROM applications
         WHERE last_validated IS NULL 
            OR last_validated < datetime('now', '-' || :days || ' days')
         ORDER BY last_validated ASC;" 2>/dev/null)
    
    # Note: Empty result is not an error - just means all apps are validated
    debug_log "$function_name" "Found applications needing validation (older than $days days)"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ============================================================================
# Getter/Setter Functions for Individual Application Fields
# ============================================================================

# ----------------------------------------------------------------------------
# db_get_app_class()
# Get the window class for an application
# Returns: app_class value (may be empty if not yet detected)
# ----------------------------------------------------------------------------
db_get_app_class() {
    local app_id="$1"
    local function_name="db_get_app_class"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_class FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved app_class for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_set_app_class()
# Store the detected window class for an application
# ----------------------------------------------------------------------------
db_set_app_class() {
    local app_id="$1"
    local app_class="$2"
    local function_name="db_set_app_class"
    local changes=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    if [[ -z "$app_class" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_class"
        debug_function_exit "$function_name"
        return 1
    fi
    
    changes=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        -cmd ".param set :app_class '$app_class'" \
        "UPDATE applications SET app_class = :app_class WHERE app_id = :app_id;
         SELECT changes();" 2>/dev/null)
    
    if [[ "$changes" -eq 1 ]]; then
        debug_log "$function_name" "Set app_class='$app_class' for $app_id"
        debug_function_exit "$function_name"
        return 0
    else
        debug_error "$function_name" "$ERR_APP_ID_INVALID" "Application not found: $app_id"
        debug_function_exit "$function_name"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# db_get_terminal_command()
# Get the terminal command for an application
# Returns: terminal_command value (may be empty)
# ----------------------------------------------------------------------------
db_get_terminal_command() {
    local app_id="$1"
    local function_name="db_get_terminal_command"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT terminal_command FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved terminal_command for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}

# ----------------------------------------------------------------------------
# db_get_app_file_path()
# Get the app file path for an application
# Returns: app_file_path value (may be empty)
# ----------------------------------------------------------------------------
db_get_app_file_path() {
    local app_id="$1"
    local function_name="db_get_app_file_path"
    local result=""
    
    debug_function_enter "$function_name" "$@"
    
    if [[ -z "$app_id" ]]; then
        debug_error "$function_name" "$ERR_MISSING_PARAMETER" "app_id"
        debug_function_exit "$function_name"
        return 1
    fi
    
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_file_path FROM applications WHERE app_id = :app_id;" 2>/dev/null)
    
    debug_log "$function_name" "Retrieved app_file_path for $app_id: ${result:-NULL}"
    debug_function_exit "$function_name"
    echo "$result"
    return 0
}