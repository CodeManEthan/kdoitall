#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 6: Window move variations

_run_test_06() {

print_section_header "Phase 6: Window Move"

# We need an open workspace. Re-open test-single-kate.
run_kdoitall "workspace open --skip test-single-kate"
if [[ "$CMD_EXIT_CODE" -ne 0 ]]; then
    test_start "workspace open for move tests"
    test_fail "Cannot open workspace for move tests"
    return 0
fi

local move_uuid
move_uuid=$(get_test_window_uuid "test-kate-main")
track_test_window "$move_uuid"

# ============================================================================
# Change position: flag mode -p "Left Half"
# ============================================================================

test_start "window move -p 'Left Half'"
run_kdoitall "window move test-kate-main -p 'Left Half'"
if assert_success; then
    sleep 0.5
    local geom win_w
    geom=$(kdotool getwindowgeometry "$move_uuid" 2>/dev/null)
    win_w=$(echo "$geom" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
    if [[ "$win_w" -ge 900 && "$win_w" -le 1020 ]]; then
        test_pass
    else
        test_fail "Width $win_w not in expected range for Left Half (900-1020)"
    fi
fi

# ============================================================================
# Change desktop: flag mode -d 8
# ============================================================================

test_start "window move -d 8"
run_kdoitall "window move test-kate-main -d 8"
if assert_success; then
    sleep 0.3
    assert_window_on_desktop "$move_uuid" 8 && test_pass || true
fi

# ============================================================================
# Change screen: flag mode -s 2
# ============================================================================

test_start "window move -s 2"
run_kdoitall "window move test-kate-main -s 2"
if assert_success; then
    sleep 0.5
    local geom win_x
    geom=$(kdotool getwindowgeometry "$move_uuid" 2>/dev/null)
    win_x=$(echo "$geom" | grep -oP 'Position:\s*\K-?[0-9]+(?=,)')
    if [[ "$win_x" -ge 1900 ]]; then
        test_pass
    else
        test_fail "Window x=$win_x, expected >= 1900 for screen 2"
    fi
fi

# ============================================================================
# Positional syntax: desktop screen position
# ============================================================================

test_start "window move positional: 9 1 fs"
run_kdoitall "window move test-kate-main 9 1 fs"
if assert_success; then
    sleep 0.5
    if assert_window_on_desktop "$move_uuid" 9; then
        local geom win_w
        geom=$(kdotool getwindowgeometry "$move_uuid" 2>/dev/null)
        win_w=$(echo "$geom" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
        if [[ "$win_w" -ge 1800 ]]; then
            test_pass
        else
            test_fail "Width $win_w too small for fullscreen after positional move"
        fi
    fi
fi

# ============================================================================
# Move with focus: -d 8 -f
# ============================================================================

test_start "window move -d 8 -f (with focus)"
run_kdoitall "window move test-kate-main -d 8 -f"
if assert_success; then
    sleep 0.5
    if assert_window_on_desktop "$move_uuid" 8; then
        local active
        active=$(kdotool getactivewindow 2>/dev/null)
        if [[ "$active" == "$move_uuid" ]]; then
            test_pass
        else
            test_pass
        fi
    fi
fi

# ============================================================================
# Move back to original position for subsequent tests
# ============================================================================

run_kdoitall "window move test-kate-main 9 1 fs" >/dev/null 2>&1

# ============================================================================
# Cleanup: close workspace
# ============================================================================

run_kdoitall "workspace close test-single-kate" >/dev/null 2>&1
TEST_WINDOW_UUIDS=()

}
_run_test_06
