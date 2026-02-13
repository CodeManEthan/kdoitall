#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Licensed under GPL-3.0-or-later. See LICENSE file.

check_dependencies() {
    local -a missing=()
    
    if ! command -v kdotool &> /dev/null; then
        missing+=("kdotool")
    fi
    
    if ! command -v ydotool &> /dev/null; then
        missing+=("ydotool")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if ! command -v bc &> /dev/null; then
        missing+=("bc")
    fi
    
    if ! command -v kscreen-doctor &> /dev/null; then
        missing+=("kscreen-doctor")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing dependencies: ${missing[*]}" >&2
        echo "" >&2
        echo "Install with:" >&2
        
        # Group packages by likely package names
        local dnf_packages=()
        for pkg in "${missing[@]}"; do
            case "$pkg" in
                kscreen-doctor)
                    dnf_packages+=("kscreen")
                    ;;
                *)
                    dnf_packages+=("$pkg")
                    ;;
            esac
        done
        
        echo "  sudo dnf install ${dnf_packages[*]}" >&2
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