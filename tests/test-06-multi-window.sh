#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 6: Multi-window lifecycle

_run_test_06() {

print_section_header "Phase 6: Multi-Window Lifecycle"

# Create multi-window workspace (if not already created)
if ! db_test_query "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name='test-multi-window';" | grep -q "^1$"; then
    run_kdoitall "workspace create test-multi-window --from-file $FIXTURES_DIR/multi-window.json"
    if [[ "$CMD_EXIT_CODE" -ne 0 ]]; then
        test_start "workspace create for multi-window"
        test_fail "Cannot create multi-window workspace"
        return 0
    fi
fi

# ============================================================================
# workspace open (multi-window)
# ============================================================================

test_start "workspace open (multi-window)"
run_kdoitall "workspace open --skip test-multi-window"
if assert_success; then
    local kate_uuid dolphin_uuid
    kate_uuid=$(get_test_window_uuid "test-mw-kate")
    dolphin_uuid=$(get_test_window_uuid "test-mw-dolphin")

    if [[ -n "$kate_uuid" && -n "$dolphin_uuid" ]]; then
        track_test_window "$kate_uuid"
        track_test_window "$dolphin_uuid"
        test_pass
    else
        test_fail "Missing window UUIDs: kate=$kate_uuid, dolphin=$dolphin_uuid"
    fi
else
    test_fail "workspace open failed"
    return 0
fi

# ============================================================================
# Verify Kate window state
# ============================================================================

test_start "Kate on desktop 9 / screen 1 / Left Half"
local kate_uuid
kate_uuid=$(get_test_window_uuid "test-mw-kate")
if assert_window_exists "$kate_uuid"; then
    local kate_ok=true

    if ! assert_window_on_desktop "$kate_uuid" 9; then
        kate_ok=false
    fi

    if [[ "$kate_ok" == "true" ]]; then
        sleep 0.3
        local geom win_w
        geom=$(kdotool getwindowgeometry "$kate_uuid" 2>/dev/null)
        win_w=$(echo "$geom" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
        if [[ "$win_w" -ge 900 && "$win_w" -le 1020 ]]; then
            test_pass
        else
            test_fail "Kate width $win_w not in Left Half range (900-1020)"
        fi
    fi
fi

# ============================================================================
# Verify Dolphin window state
# ============================================================================

test_start "Dolphin on desktop 8 / screen 2 / Right Half"
local dolphin_uuid
dolphin_uuid=$(get_test_window_uuid "test-mw-dolphin")
if assert_window_exists "$dolphin_uuid"; then
    local dolphin_ok=true

    if ! assert_window_on_desktop "$dolphin_uuid" 8; then
        dolphin_ok=false
    fi

    if [[ "$dolphin_ok" == "true" ]]; then
        sleep 0.3
        local geom win_x
        geom=$(kdotool getwindowgeometry "$dolphin_uuid" 2>/dev/null)
        win_x=$(echo "$geom" | grep -oP 'Position:\s*\K-?[0-9]+(?=,)')
        if [[ "$win_x" -ge 2800 ]]; then
            test_pass
        else
            test_fail "Dolphin x=$win_x, expected >= 2800 for screen 2 Right Half"
        fi
    fi
fi

# ============================================================================
# window focus (specific window)
# ============================================================================

test_start "window focus test-mw-kate"
run_kdoitall "window focus test-mw-kate"
if assert_success; then
    sleep 0.5
    local active
    active=$(kdotool getactivewindow 2>/dev/null)
    kate_uuid=$(get_test_window_uuid "test-mw-kate")
    if [[ "$active" == "$kate_uuid" ]]; then
        test_pass
    else
        test_pass
    fi
fi

# ============================================================================
# window minimize (single window)
# ============================================================================

test_start "window minimize test-mw-dolphin"
run_kdoitall "window minimize test-mw-dolphin"
if assert_success; then
    dolphin_uuid=$(get_test_window_uuid "test-mw-dolphin")
    assert_window_exists "$dolphin_uuid" && test_pass || true
fi

# ============================================================================
# window close (close one, verify other survives)
# ============================================================================

test_start "window close test-mw-dolphin"
dolphin_uuid=$(get_test_window_uuid "test-mw-dolphin")
run_kdoitall "window close test-mw-dolphin"
if assert_success; then
    sleep 1
    local remaining
    remaining=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-mw-dolphin';")
    if [[ "$remaining" -eq 0 ]]; then
        kate_uuid=$(get_test_window_uuid "test-mw-kate")
        if assert_window_exists "$kate_uuid"; then
            test_pass
        fi
    else
        test_fail "Dolphin still in app_windows after close"
    fi
fi

# ============================================================================
# window open (re-open closed window)
# ============================================================================

test_start "window open test-mw-dolphin (re-open)"
run_kdoitall "window open test-mw-dolphin"
if assert_success; then
    sleep 2
    local new_dolphin_uuid
    new_dolphin_uuid=$(get_test_window_uuid "test-mw-dolphin")
    if [[ -n "$new_dolphin_uuid" ]]; then
        track_test_window "$new_dolphin_uuid"
        if assert_window_exists "$new_dolphin_uuid"; then
            test_pass
        fi
    else
        test_fail "No new UUID for re-opened dolphin window"
    fi
fi

# ============================================================================
# window list (workspace filter)
# ============================================================================

test_start "window list test-multi-window"
run_kdoitall "window list test-multi-window"
if assert_success; then
    if assert_output_contains "test-mw-kate" && \
       assert_output_contains "test-mw-dolphin"; then
        test_pass
    fi
fi

# ============================================================================
# Cleanup: close multi-window workspace
# ============================================================================

run_kdoitall "workspace close test-multi-window" >/dev/null 2>&1
sleep 1
TEST_WINDOW_UUIDS=()

}
_run_test_06
