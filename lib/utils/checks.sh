#!/bin/bash
# Dependency checking functions

check_dependencies() {
    local -a missing=()
    
    if ! command -v kdotool &> /dev/null; then
        missing+=("kdotool")
    fi
    
    if ! command -v ydotool &> /dev/null; then
        missing+=("ydotool")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing dependencies: ${missing[*]}" >&2
        echo "" >&2
        echo "Install with:" >&2
        echo "  sudo dnf install ${missing[*]}" >&2
        exit 1
    fi
}

check_and_set_guard() {
    local guard_var="$1"
    
    if [[ -n "${!guard_var:-}" ]]; then
        return 1  # Already sourced (failure = don't continue)
    fi
    
    # Set the guard variable in the caller's scope
    printf -v "$guard_var" "1"
    return 0  # Not sourced yet (success = continue)
}