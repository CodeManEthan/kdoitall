#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 12: Multiple independent workspaces open simultaneously

_run_test_12() {

print_section_header "Phase 12: Simultaneous Workspaces"

# Setup Firefox for workspace-beta
setup_test_app "org.mozilla.firefox" "multi" "org.mozilla.firefox"

# ============================================================================
# Create both workspaces
# ============================================================================

test_start "create workspace alpha (Kate + Dolphin)"
run_kdoitall "workspace create test-ws-alpha --from-file $FIXTURES_DIR/workspace-alpha.json"
if assert_success; then
    test_pass
else
    test_fail "Cannot create workspace alpha"
    return 0
fi

test_start "create workspace beta (Firefox)"
run_kdoitall "workspace create test-ws-beta --from-file $FIXTURES_DIR/workspace-beta.json"
if assert_success; then
    test_pass
else
    test_fail "Cannot create workspace beta"
    return 0
fi

# ============================================================================
# Open workspace alpha
# ============================================================================

test_start "open workspace alpha"
run_kdoitall "workspace open --skip test-ws-alpha"
if assert_success; then
    local kate_uuid dolphin_uuid
    kate_uuid=$(get_test_window_uuid "test-alpha-kate")
    dolphin_uuid=$(get_test_window_uuid "test-alpha-dolphin")
    if [[ -n "$kate_uuid" && -n "$dolphin_uuid" ]]; then
        track_test_window "$kate_uuid"
        track_test_window "$dolphin_uuid"
        test_pass
    else
        test_fail "Missing alpha UUIDs: kate=$kate_uuid, dolphin=$dolphin_uuid"
    fi
else
    test_fail "workspace open alpha failed"
    return 0
fi

# ============================================================================
# Open workspace beta
# ============================================================================

test_start "open workspace beta"
run_kdoitall "workspace open --skip test-ws-beta"
if assert_success; then
    local ff_uuid
    ff_uuid=$(get_test_window_uuid "test-beta-firefox")
    if [[ -n "$ff_uuid" ]]; then
        track_test_window "$ff_uuid"
        test_pass
    else
        test_fail "Missing beta UUID for test-beta-firefox"
    fi
else
    test_fail "workspace open beta failed"
fi

# ============================================================================
# Verify both workspaces are active
# ============================================================================

test_start "both workspaces active in DB"
local alpha_active beta_active
alpha_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-ws-alpha';")
beta_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-ws-beta';")
if [[ "$alpha_active" == "1" && "$beta_active" == "1" ]]; then
    test_pass
else
    test_fail "alpha is_active=$alpha_active, beta is_active=$beta_active (expected both 1)"
fi

test_start "status shows both active workspaces"
run_kdoitall "status"
if assert_success; then
    if assert_output_contains "test-ws-alpha" && \
       assert_output_contains "test-ws-beta"; then
        test_pass
    fi
fi

# ============================================================================
# Verify alpha windows still alive after beta opened
# ============================================================================

test_start "alpha windows still alive"
local kate_uuid dolphin_uuid
kate_uuid=$(get_test_window_uuid "test-alpha-kate")
dolphin_uuid=$(get_test_window_uuid "test-alpha-dolphin")
if assert_window_exists "$kate_uuid" && assert_window_exists "$dolphin_uuid"; then
    test_pass
else
    test_fail "Alpha windows died after opening beta"
fi

# ============================================================================
# Close alpha — beta should survive
# ============================================================================

test_start "close alpha, beta survives"
run_kdoitall "workspace close test-ws-alpha"
if assert_success; then
    local alpha_active
    alpha_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-ws-alpha';")
    local alpha_windows
    alpha_windows=$(db_count_test_windows "test-ws-alpha")

    local beta_active
    beta_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-ws-beta';")
    local ff_uuid
    ff_uuid=$(get_test_window_uuid "test-beta-firefox")

    if [[ "$alpha_active" == "0" && "$alpha_windows" -eq 0 && \
          "$beta_active" == "1" && -n "$ff_uuid" ]]; then
        if assert_window_exists "$ff_uuid"; then
            test_pass
        fi
    else
        test_fail "alpha_active=$alpha_active windows=$alpha_windows, beta_active=$beta_active ff_uuid=$ff_uuid"
    fi
fi

# ============================================================================
# Close beta
# ============================================================================

test_start "close beta"
run_kdoitall "workspace close test-ws-beta"
if assert_success; then
    local beta_active
    beta_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-ws-beta';")
    local beta_windows
    beta_windows=$(db_count_test_windows "test-ws-beta")
    if [[ "$beta_active" == "0" && "$beta_windows" -eq 0 ]]; then
        test_pass
    else
        test_fail "beta_active=$beta_active, beta_windows=$beta_windows"
    fi
fi

sleep 1
TEST_WINDOW_UUIDS=()

}
_run_test_12
