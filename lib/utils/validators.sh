#!/bin/bash

# Sources: 
# core/debug.sh
# core/error_codes.sh

safe_name() {
    local name="$1"
    local function_name="safe_name"

    debug_function_enter "$function_name" "$@"

    # Escape special characters
    name="${name//\(/\\(}"
    name="${name//\)/\\)}"
    name="${name//\[/\\[}"
    name="${name//\]/\\]}"

    # Pass Name
    debug_log "$function_name" "$name"

    debug_function_exit "$function_name"
    echo "$name" 
}

safe_file() {
    local file_path="$1"
    local safe_file_path=""
    local function_name="safe_file"

    debug_function_enter "$function_name" "$@"
    
    # Apply 'safe_name' to file_path (if file exists and is not empty)
    if [[ -f "$file_path" ]]; then
        if [[ -s "$file_path" ]]; then
            safe_file_path=$(safe_name "$file_path")

            # Pass Safe File Path
            debug_log "$function_name" "Renamed $file_path to $safe_file_path"

            debug_function_exit "$function_name"
            echo "$safe_file_path"
            return 0
        else
            debug_error "$function_name" "$ERR_FILE_IS_EMPTY" "$file_path"
            debug_function_exit "$function_name"
            return 1
        fi
    else
        debug_error "$function_name" "$ERR_FILE_NOT_FOUND" "$file_path"
        debug_function_exit "$function_name"
        return 1
    fi
}

safe_directory() {
    local directory_path="$1"
    local safe_directory_path=""
    local function_name="safe_directory"

    debug_function_enter "$function_name" "$@"
    
    # Apply 'safe_name' to directory_path (if directory exists)
    if [[ -d "$directory_path" ]]; then
        safe_directory_path=$(safe_name "$directory_path")

        # Pass Safe Directory Path
        debug_log "$function_name" "Renamed $directory_path to $safe_directory_path"

        debug_function_exit "$function_name"
        echo "$safe_directory_path"
        return 0
    fi
    
    debug_error "$function_name" "$ERR_DIRECTORY_NOT_FOUND" "$directory_path"
    debug_function_exit "$function_name"
    return 1
}





