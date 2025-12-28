#!/bin/bash

# Sources: 
# core/debug.sh
# core/error_codes.sh

safe_name() {
    local name="$1"
    local function_name="safe_name"

    debug_log "CALL FUNCTION: $function_name" "verbose"

    # Escape special characters
    name="${name//\(/\\(}"
    name="${name//\)/\\)}"
    name="${name//\[/\\[}"
    name="${name//\]/\\]}"

    # Pass Name
    debug_log "$function_name: $name" "verbose"
    echo "$name" 
}

safe_file() {
    local file_path="$1"
    local safe_file_path
    local function_name="safe_file"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    # Apply 'safe_name' to file_path (if file exists and is not empty)
    if [[ -f "$file_path" ]]; then
        if [[ -s "$file_path" ]]; then
            safe_file_path=$(safe_name "$file_path")

            # Pass Safe File Path
            debug_log "$function_name: Renamed $file_path to $safe_file_path" "verbose"
            echo "$safe_file_path"
            return 0
        else
            debug_log "$function_name: ${ERROR_MESSAGES[$ERR_EMPTY_FILE]} - $file_path"
            return 1
        fi
    else
        debug_log "$function_name: ${ERROR_MESSAGES[$ERR_FILE_NOT_FOUND]} - $file_path"
        return 1
    fi
}

safe_directory() {
    local directory_path="$1"
    local safe_directory_path
    local function_name="safe_directory"

    debug_log "CALL FUNCTION: $function_name" "verbose"
    
    # Apply 'safe_name' to directory_path (if directory exists)
    if [[ -d "$directory_path" ]]; then
        safe_directory_path=$(safe_name "$directory_path")

        # Pass Safe Directory Path
        debug_log "$function_name: Renamed $directory_path to $safe_directory_path" "verbose"
        echo "$safe_directory_path"
        return 0
    fi
    
    debug_log "$function_name: ${ERROR_MESSAGES[$ERR_DIRECTORY_NOT_FOUND]} - $directory_path"
    return 1
}





