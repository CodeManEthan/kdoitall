#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 16: Active workspace guard (block edit/replace/delete on active workspace)

_run_test_16() {

print_section_header "Phase 16: Active Workspace Guard"

# ============================================================================
# Create and open workspace
# ============================================================================

test_start "guard workspace create + open"
run_kdoitall "workspace create test-guard-ws --from-file $FIXTURES_DIR/guard-workspace.json"
if ! assert_success; then
    test_fail "Cannot create guard workspace"
    return 0
fi
run_kdoitall "workspace open --skip test-guard-ws"
if assert_success; then
    local uuid
    uuid=$(get_test_window_uuid "test-guard-kate")
    if [[ -n "$uuid" ]]; then
        track_test_window "$uuid"
        local is_active
        is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-guard-ws';")
        if [[ "$is_active" == "1" ]]; then
            test_pass
        else
            test_fail "is_active=$is_active, expected 1"
        fi
    else
        test_fail "No UUID for test-guard-kate"
    fi
else
    test_fail "workspace open failed"
    return 0
fi

# ============================================================================
# Delete active workspace should be blocked
# ============================================================================

test_start "delete active workspace blocked"
CMD_OUTPUT=$(echo "y" | $KDOITALL --info workspace delete test-guard-ws 2>&1) || true
CMD_EXIT_CODE=$?
if [[ "$CMD_EXIT_CODE" -ne 0 ]]; then
    if echo "$CMD_OUTPUT" | grep -qi "active"; then
        test_pass
    else
        test_fail "Command failed but error message doesn't mention 'active': $CMD_OUTPUT"
    fi
else
    test_fail "Delete succeeded on active workspace (expected failure)"
fi

# ============================================================================
# Replace active workspace should be blocked
# ============================================================================

test_start "replace active workspace blocked"
run_kdoitall "workspace create test-guard-ws --from-file $FIXTURES_DIR/guard-workspace.json --replace"
if [[ "$CMD_EXIT_CODE" -ne 0 ]]; then
    if assert_output_contains "active"; then
        test_pass
    else
        test_fail "Replace failed but error doesn't mention 'active'"
    fi
else
    test_fail "Replace succeeded on active workspace (expected failure)"
fi

# ============================================================================
# Verify workspace is unchanged
# ============================================================================

test_start "workspace unchanged after blocked operations"
local uuid
uuid=$(get_test_window_uuid "test-guard-kate")
local is_active
is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-guard-ws';")
if [[ "$is_active" == "1" && -n "$uuid" ]]; then
    if assert_window_exists "$uuid"; then
        test_pass
    fi
else
    test_fail "Workspace state changed: is_active=$is_active, uuid=$uuid"
fi

# ============================================================================
# Close workspace
# ============================================================================

test_start "close guard workspace"
run_kdoitall "workspace close test-guard-ws"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-guard-ws';")
    if [[ "$is_active" == "0" ]]; then
        test_pass
    else
        test_fail "is_active=$is_active after close, expected 0"
    fi
fi

sleep 1
TEST_WINDOW_UUIDS=()

# ============================================================================
# Delete inactive workspace should succeed
# ============================================================================

test_start "delete inactive workspace succeeds"
CMD_OUTPUT=$(echo "y" | $KDOITALL --info workspace delete test-guard-ws 2>&1) || true
CMD_EXIT_CODE=$?
if [[ "$CMD_EXIT_CODE" -eq 0 ]]; then
    local ws_count
    ws_count=$(db_test_query "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name='test-guard-ws';")
    if [[ "$ws_count" -eq 0 ]]; then
        test_pass
    else
        test_fail "Workspace still in DB after delete"
    fi
else
    test_fail "Delete failed on inactive workspace (exit=$CMD_EXIT_CODE)"
fi

}
_run_test_16
