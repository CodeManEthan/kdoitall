#!/bin/bash

# Sources:
# core/common.sh
# core/debug.sh
# core/error_codes.sh

db_get_uuid_by_window_name() {
    local window_name="$1"
    local uuid=""
    local function_name="get_uuid_by_window_name"

    debug_function_enter "$function_name" "$@"

    # Get UUID for Window Name from 'windows' table
    uuid=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        "SELECT uuid FROM app_windows WHERE window_name = :window_name;" 2>/dev/null)

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$window_name' → '$uuid'"
    
    debug_function_exit "$function_name"
    echo "$uuid"
}

db_get_window_name_by_uuid() {
    local uuid="$1"
    local window_name=""
    local function_name="get_window_by_uuid"

    debug_function_enter "$function_name" "$@"

    # Get Window Name for UUID from 'windows' table
    window_name=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :uuid '$uuid'" \
        "SELECT window_name FROM app_windows WHERE uuid = :uuid;" 2>/dev/null)

    if [[ -z "$window_name" ]]; then
        debug_error "$function_name" "$ERR_WINDOW_NAME_NOT_FOUND" "$uuid"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass Window Name
    debug_log "$function_name" "'$uuid' → '$window_name'"

    debug_function_exit "$function_name"
    echo "$window_name"
}

db_get_tab_by_tab_name() {
    local window_name="$1"
    local tab_name="$2"
    local tab_number=""
    local function_name="get_tab_by_tab_name"

    debug_function_enter "$function_name" "$@"

    # Get Tab Number for Window Name & Tab Name from 'tabs' table
    tab_number=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window_name '$window_name'" \
        -cmd ".param set :tab_name '$tab_name'" \
        "SELECT tab FROM tabs WHERE window_name = :window_name AND tab_name = :tab_name;" 2>/dev/null)

    if [[ -z "$tab_number" ]]; then
        debug_error "$function_name" "$ERR_TAB_NUMBER_NOT_FOUND"  "$window_name - $tab_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass Tab Number
    debug_log "$function_name" "'$window_name' '$tab_name' → '$tab_number'"
    
    debug_function_exit "$function_name"
    echo "$tab_number"
}

db_check_window_exists_by_window_name() {
    local window_name="$1"
    local uuid=""
    local function_name="check_window_exists_by_window_name"

    debug_function_enter "$function_name" "$@"

    # Get UUID by Window Name
    uuid=$(db_get_uuid_by_window_name "$window_name")

    if [[ -z "$uuid" ]]; then
        debug_error "$function_name" "$ERR_UUID_NOT_FOUND" "$window_name"
        debug_function_exit "$function_name"
        return 1
    fi

    # Pass UUID
    debug_log "$function_name" "'$window_name' ($uuid) already exists."

    debug_function_exit "$function_name"
    echo "$uuid"    
}


db_add_window() {
    local window_name="$1"
    local workspace_name="$2"
    local uuid="$3"
    local class="$4"
    local function_name="db_add_window"

    debug_function_enter "$function_name" "$@"
    
    # Add entry to 'app_windows' table
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :workspace '$workspace_name'" \
        -cmd ".param set :window '$window_name'" \
        -cmd ".param set :uuid '$uuid'" \
        -cmd ".param set :class '$class'" \
        "INSERT INTO app_windows (workspace_name, window_name, uuid, class, is_tab)
         VALUES (:workspace, :window, :uuid, :class, FALSE);"
    
    debug_log "$function_name" "Added window '$window_name' (workspace: '$workspace_name', uuid: '$uuid', class: '$class')"
    debug_function_exit "$function_name"
}

db_delete_window() {
    local window_name="$1"
    local function_name="db_delete_window"

    debug_function_enter "$function_name" "$@"

    # Delete entry from 'app_windows' table
    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window '$window_name'" \
        "DELETE FROM app_windows WHERE window_name = :window;"
    
    debug_log "$function_name" "Deleted window '$window_name'"
    debug_function_exit "$function_name"
}

db_claim_window() {
    local new_window_name="$1"
    local new_workspace_name="$2"
    local uuid="$3"
    local function_name="db_claim_window"

    debug_function_enter "$function_name" "$@"

    sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :window '$new_window_name'" \
        -cmd ".param set :workspace '$new_workspace_name'" \
        -cmd ".param set :uuid '$uuid'" \
        "UPDATE app_windows 
         SET window_name = :window,
             workspace_name = :workspace
         WHERE uuid = :uuid;"

    debug_log "$function_name" "Claimed window '$new_window_name' (workspace: '$new_workspace_name', uuid: '$uuid')"
    debug_function_exit "$function_name"
}

db_add_existing_windows() {
    local -n uuids_ref="$1"
    local -n classes_ref="$2"
    local window_name=""
    local workspace_name="~auto:workspace"
    local function_name="db_add_existing_windows"

    # Track class counts for unique naming
    declare -A class_counts

    debug_function_enter "$function_name" "$1" "$2"
    
    debug_log "$function_name" "===== ARRAYS FROM KDOTOOL ====="
    debug_array "$1"
    debug_array "$2"

    for i in "${!uuids_ref[@]}"; do
        local class="${classes_ref[$i]}"
        local uuid="${uuids_ref[$i]}"
        
        # Increment counter for this class
        if [[ -z "${class_counts[$class]+_}" ]]; then
            class_counts[$class]=1
        else
            ((class_counts[$class]++))
        fi
        
        # Create unique window name with counter
        window_name="~auto:${class}:${class_counts[$class]}"

        debug_log "$function_name" "Attempting INSERT: window_name='$window_name', uuid='$uuid', class='$class'"

        # Check if UUID already exists first
        local existing_check=""
        existing_check=$(sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :uuid '$uuid'" \
            "SELECT window_name FROM app_windows WHERE uuid = :uuid;" 2>/dev/null)
        
        if [[ -n "$existing_check" ]]; then
            debug_log "$function_name" "UUID ALREADY IN DB: uuid='$uuid' exists as window_name='$existing_check'"
            continue
        fi

        local changes=""
        changes=$(sqlite3 "$KDOITALL_DB" \
            -cmd ".param init" \
            -cmd ".param set :workspace '$workspace_name'" \
            -cmd ".param set :window '$window_name'" \
            -cmd ".param set :uuid '$uuid'" \
            -cmd ".param set :class '$class'" \
            "INSERT OR IGNORE INTO app_windows (workspace_name, window_name, uuid, class, is_tab) 
            VALUES (:workspace, :window, :uuid, :class, FALSE);
            SELECT changes();")
        
        if [ "$changes" -eq 1 ]; then
            debug_log "$function_name" "✓ INSERTED: window_name='$window_name', uuid='$uuid', class='$class'"
        else
            debug_log "$function_name" "✗ INSERT FAILED (window_name conflict?): window_name='$window_name', uuid='$uuid'"
        fi
    done

    debug_function_exit "$function_name"
}

db_delete_stale_windows() {
    local -n existing_uuids_ref="$1"
    local -n db_uuids_ref="$2"
    local -A existing_lookup=()
    local uuid_to_delete=""
    local function_name="db_delete_stale_windows"

    debug_function_enter "$function_name" "$1" "$2"
    
    debug_array "$1" 
    debug_array "$2"

    # Build lookup table for O(1) checking
    for uuid in "${existing_uuids_ref[@]}"; do
        existing_lookup["$uuid"]=1
    done
    
    debug_log "$function_name" "Built lookup table with ${#existing_lookup[@]} entries"
    
    # Delete UUIDs that don't exist anymore
    for uuid_to_delete in "${db_uuids_ref[@]}"; do
        if [[ ! -v existing_lookup[$uuid_to_delete] ]]; then
            sqlite3 "$KDOITALL_DB" \
                -cmd ".param init" \
                -cmd ".param set :uuid '$uuid_to_delete'" \
                "DELETE FROM app_windows WHERE uuid = :uuid;"
            
            # Check if row was actually deleted
            local changes=""
            changes=$(sqlite3 "$KDOITALL_DB" "SELECT changes()")
            
            if [ "$changes" -eq 1 ]; then
                debug_log "$function_name" "DELETED: Stale window with uuid='$uuid_to_delete'"
                echo "Deleted stale window: $uuid_to_delete"
            else
                debug_log "$function_name" "DELETE FAILED: uuid='$uuid_to_delete' not found in database"
            fi
        else
            debug_log "$function_name" "KEPT: uuid='$uuid_to_delete' still exists"
        fi
    done

    debug_function_exit "$function_name"
}

#!/bin/bash

# ============================================================================
# Application Registry Database Functions
# ============================================================================
# These functions should be added to lib/core/database.sh
# They handle CRUD operations for the application registry tables

# ----------------------------------------------------------------------------
# db_add_application()
# Insert or update an application in the database
# ----------------------------------------------------------------------------
db_add_application() {
    local app_id="$1"
    local display_name="$2"
    local desktop_file_path="$3"
    local has_terminal_launch="$4"
    local has_desktop_launch="$5"
    local app_file_path="$6"
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
        -cmd ".param set :has_terminal '$terminal_bool'" \
        -cmd ".param set :has_desktop '$desktop_bool'" \
        -cmd ".param set :app_file '$app_file_path'" \
        "INSERT OR REPLACE INTO applications (
            app_id, display_name, desktop_file_path,
            has_terminal_launch, has_desktop_launch,
            app_file_path, last_validated
        ) VALUES (
            :app_id, :display_name, :desktop_file,
            :has_terminal, :has_desktop,
            :app_file, datetime('now')
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
# Returns: app_id|display_name|desktop_file_path|has_terminal_launch|has_desktop_launch|app_file_path|last_validated
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
    
    # Query database
    result=$(sqlite3 "$KDOITALL_DB" \
        -cmd ".param init" \
        -cmd ".param set :app_id '$app_id'" \
        "SELECT app_id, display_name, desktop_file_path,
                has_terminal_launch, has_desktop_launch,
                app_file_path, last_validated
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
#          app_id|display_name|has_terminal_launch|has_desktop_launch|app_file_path
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
                          has_desktop_launch, app_file_path
                   FROM applications
                   ORDER BY display_name;"
            ;;
        terminal)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch, app_file_path
                   FROM applications
                   WHERE has_terminal_launch = TRUE
                   ORDER BY display_name;"
            ;;
        desktop)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch, app_file_path
                   FROM applications
                   WHERE has_desktop_launch = TRUE
                   ORDER BY display_name;"
            ;;
        both)
            query="SELECT app_id, display_name, has_terminal_launch,
                          has_desktop_launch, app_file_path
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