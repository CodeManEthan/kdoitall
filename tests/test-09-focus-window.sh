#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 09: Focus window configuration

_run_test_09() {

print_section_header "Test 09: Focus Window Configuration"

# ============================================================================
# Create workspace with focus_window set to Dolphin
# ============================================================================

test_start "focus workspace create"
run_kdoitall "workspace create test-focus-window --from-file $FIXTURES_DIR/focus-window.json"
if assert_success; then
    local focus_name
    focus_name=$(db_test_query "SELECT focus_window_name FROM workspace_definitions WHERE workspace_name='test-focus-window';")
    if [[ "$focus_name" == "test-focus-dolphin" ]]; then
        test_pass
    else
        test_fail "focus_window_name='$focus_name', expected 'test-focus-dolphin'"
    fi
fi

# ============================================================================
# Open workspace — both windows should launch
# ============================================================================

test_start "focus workspace open"
run_kdoitall "workspace open --skip test-focus-window"
if assert_success; then
    local kate_uuid dolphin_uuid
    kate_uuid=$(get_test_window_uuid "test-focus-kate")
    dolphin_uuid=$(get_test_window_uuid "test-focus-dolphin")

    if [[ -n "$kate_uuid" && -n "$dolphin_uuid" ]]; then
        track_test_window "$kate_uuid"
        track_test_window "$dolphin_uuid"
        test_pass
    else
        test_fail "Missing window UUIDs: kate=$kate_uuid, dolphin=$dolphin_uuid"
    fi
else
    test_fail "workspace open failed"
    # Cleanup and bail
    run_kdoitall "workspace close test-focus-window" >/dev/null 2>&1
    sleep 1
    TEST_WINDOW_UUIDS=()
    return 0
fi

# ============================================================================
# Verify Dolphin (focus target) is the active window
# ============================================================================

test_start "active window is focus target (Dolphin)"
local dolphin_uuid
dolphin_uuid=$(get_test_window_uuid "test-focus-dolphin")
local focus_ok=false
local attempt
for attempt in $(seq 1 5); do
    sleep 0.5
    local active
    active=$(kdotool getactivewindow 2>/dev/null)
    if [[ "$active" == "$dolphin_uuid" ]]; then
        focus_ok=true
        break
    fi
done
if [[ "$focus_ok" == "true" ]]; then
    test_pass
else
    local actual_active
    actual_active=$(kdotool getactivewindow 2>/dev/null)
    test_fail "Active window is $actual_active, expected $dolphin_uuid (Dolphin)"
fi

# ============================================================================
# Cleanup: close workspace
# ============================================================================

run_kdoitall "workspace close test-focus-window" >/dev/null 2>&1
sleep 1
TEST_WINDOW_UUIDS=()

}
_run_test_09
