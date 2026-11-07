#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 11: Auto-detect sync after external window kill

_run_test_11() {

print_section_header "Test 11: Auto-Detect Sync"

# Ensure workspace exists (re-create if needed)
if ! db_test_query "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name='test-single-kate';" | grep -q "^1$"; then
    run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate.json"
fi

# ============================================================================
# Open workspace to get a tracked window
# ============================================================================

test_start "open workspace for sync test"
run_kdoitall "workspace open --skip test-single-kate"
if assert_success; then
    local uuid
    uuid=$(get_test_window_uuid "test-kate-main")
    if [[ -n "$uuid" ]]; then
        track_test_window "$uuid"
        test_pass
    else
        test_fail "No UUID for test-kate-main"
        return 0
    fi
else
    test_fail "workspace open failed"
    return 0
fi

# ============================================================================
# Kill window externally via kdotool
# ============================================================================

test_start "kill window externally"
local uuid
uuid=$(get_test_window_uuid "test-kate-main")
kdotool windowclose "$uuid" 2>/dev/null || true
sleep 2

# Verify window is actually dead
local window_dead=false
local attempt
for attempt in $(seq 1 5); do
    if [[ -z "$(kdotool getwindowclassname "$uuid" 2>/dev/null)" ]]; then
        window_dead=true
        break
    fi
    sleep 1
done
if [[ "$window_dead" == "true" ]]; then
    test_pass
else
    test_fail "Window $uuid still alive after external close"
    # Cleanup and bail
    run_kdoitall "workspace close test-single-kate" >/dev/null 2>&1
    sleep 1
    TEST_WINDOW_UUIDS=()
    return 0
fi

# ============================================================================
# DB should still have the stale entry (no sync yet)
# ============================================================================

test_start "stale DB entry exists before sync"
local stale_count
stale_count=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-kate-main';")
if [[ "$stale_count" -ge 1 ]]; then
    test_pass
else
    test_fail "app_windows row already gone (count=$stale_count) — sync ran too early?"
fi

# ============================================================================
# Trigger auto-detect sync via status command
# ============================================================================

test_start "trigger auto-detect sync"
run_kdoitall "status"
if assert_success; then
    test_pass
fi

# ============================================================================
# Verify stale entry was cleaned up
# ============================================================================

test_start "stale DB entry removed after sync"
local remaining
remaining=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-kate-main';")
if [[ "$remaining" -eq 0 ]]; then
    test_pass
else
    test_fail "app_windows row still exists after sync (count=$remaining)"
fi

# ============================================================================
# Re-open the window via window open command
# ============================================================================

test_start "re-open window after sync"
run_kdoitall "window open test-kate-main"
if assert_success; then
    sleep 2
    local new_uuid
    new_uuid=$(get_test_window_uuid "test-kate-main")
    if [[ -n "$new_uuid" ]]; then
        track_test_window "$new_uuid"
        if retry 5 1 assert_window_exists "$new_uuid"; then
            test_pass
        else
            test_fail "Re-opened window $new_uuid not found via kdotool"
        fi
    else
        test_fail "No new UUID after re-open"
    fi
fi

# ============================================================================
# Cleanup: close workspace
# ============================================================================

run_kdoitall "workspace close test-single-kate" >/dev/null 2>&1
sleep 1
TEST_WINDOW_UUIDS=()

}
_run_test_11
