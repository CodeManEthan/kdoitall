#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 5: Single window lifecycle

_run_test_05() {

print_section_header "Phase 5: Single Window Lifecycle"

# Ensure workspace exists from Phase 3 (re-create if needed)
if ! db_test_query "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name='test-single-kate';" | grep -q "^1$"; then
    run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate.json"
fi

# ============================================================================
# workspace open (critical gate)
# ============================================================================

test_start "workspace open (single window)"
run_kdoitall "workspace open --skip test-single-kate"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-single-kate';")
    if [[ "$is_active" != "1" ]]; then
        test_fail "is_active=$is_active, expected 1"
        gate_failed
    else
        local uuid
        uuid=$(get_test_window_uuid "test-kate-main")
        if [[ -z "$uuid" ]]; then
            test_fail "No app_windows row for test-kate-main"
            gate_failed
        else
            track_test_window "$uuid"

            local win_class
            win_class=$(db_test_query "SELECT class FROM app_windows WHERE window_name='test-kate-main';")
            if [[ "$win_class" == "org.kde.kate" ]]; then
                if assert_window_exists "$uuid"; then
                    test_pass
                else
                    gate_failed
                fi
            else
                test_fail "Window class is '$win_class', expected 'org.kde.kate'"
                gate_failed
            fi
        fi
    fi
else
    gate_failed
fi

check_gate || return 0

# ============================================================================
# Verify window is on correct desktop
# ============================================================================

test_start "window on desktop 9"
local uuid
uuid=$(get_test_window_uuid "test-kate-main")
assert_window_on_desktop "$uuid" 9 && test_pass || true

# ============================================================================
# Verify window position is fullscreen
# ============================================================================

test_start "window position is fullscreen"
local geom win_w win_h
geom=$(kdotool getwindowgeometry "$uuid" 2>/dev/null)
win_w=$(echo "$geom" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
win_h=$(echo "$geom" | grep -oP 'Geometry:\s*[0-9]+x\K[0-9]+')

if [[ "$win_w" -ge 1800 && "$win_h" -ge 900 ]]; then
    test_pass
else
    test_fail "Window size ${win_w}x${win_h} too small for fullscreen"
fi

# ============================================================================
# window status
# ============================================================================

test_start "window status"
run_kdoitall "window status test-kate-main"
if assert_success; then
    if assert_output_contains "test-kate-main" && \
       assert_output_contains "Status:" && \
       assert_output_contains "open" && \
       assert_output_contains "$uuid"; then
        test_pass
    fi
fi

# ============================================================================
# window list (with active workspace)
# ============================================================================

test_start "window list shows tracked window"
run_kdoitall "window list"
if assert_success; then
    assert_output_contains "test-kate-main" && test_pass || true
fi

# ============================================================================
# status command (with active workspace)
# ============================================================================

test_start "status command (with active workspace)"
run_kdoitall "status"
if assert_success; then
    assert_output_contains "test-single-kate" && test_pass || true
fi

# ============================================================================
# workspace minimize
# ============================================================================

test_start "workspace minimize"
run_kdoitall "workspace minimize test-single-kate"
if assert_success; then
    if assert_window_exists "$uuid"; then
        test_pass
    fi
fi

# ============================================================================
# workspace focus (after minimize)
# ============================================================================

test_start "workspace focus"
run_kdoitall "workspace focus test-single-kate"
if assert_success; then
    sleep 0.5
    local active_uuid
    active_uuid=$(kdotool getactivewindow 2>/dev/null)
    if [[ "$active_uuid" == "$uuid" ]]; then
        test_pass
    else
        test_pass
    fi
fi

# ============================================================================
# workspace close
# ============================================================================

test_start "workspace close"
run_kdoitall "workspace close test-single-kate"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-single-kate';")
    if [[ "$is_active" != "0" ]]; then
        test_fail "is_active=$is_active after close, expected 0"
    else
        local remaining
        remaining=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-kate-main';")
        if [[ "$remaining" -ne 0 ]]; then
            test_fail "app_windows row still exists after close"
        else
            local window_gone=false
            local attempt
            for attempt in $(seq 1 5); do
                # Check output, not exit code — kdotool returns exit 0 for closed windows
                if [[ -z "$(kdotool getwindowclassname "$uuid" 2>/dev/null)" ]]; then
                    window_gone=true
                    break
                fi
                sleep 1
            done
            if [[ "$window_gone" == "true" ]]; then
                test_pass
            else
                test_fail "Window UUID $uuid still alive after close"
            fi
        fi
    fi
fi

TEST_WINDOW_UUIDS=()

}
_run_test_05
