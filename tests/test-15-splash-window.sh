#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 15: Splash window detection (digiKam)

_run_test_15() {

print_section_header "Test 15: Splash Window Detection"

# Setup: register digiKam, skip safe mode, reset splash status to unknown
setup_test_app "org.kde.digikam" "" ""
db_set_test_splash "org.kde.digikam" "unknown" 0

# ============================================================================
# Create workspace
# ============================================================================

test_start "digiKam workspace create"
run_kdoitall "workspace create test-splash-digikam --from-file $FIXTURES_DIR/splash-digikam.json"
if assert_success; then
    test_pass
fi

# ============================================================================
# First open — splash auto-detection
# ============================================================================

test_start "digiKam workspace open (splash auto-detect)"
run_kdoitall "workspace open --skip test-splash-digikam"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-splash-digikam';")
    if [[ "$is_active" != "1" ]]; then
        test_fail "is_active=$is_active, expected 1"
    else
        local uuid
        uuid=$(get_test_window_uuid "test-digikam-main")
        if [[ -z "$uuid" ]]; then
            test_fail "No app_windows row for test-digikam-main"
        else
            track_test_window "$uuid"
            # digiKam can be slow; use generous retries
            if retry 15 1 assert_window_exists "$uuid"; then
                test_pass
            else
                test_fail "Window $uuid not found via kdotool"
            fi
        fi
    fi
else
    test_fail "workspace open failed"
    return 0
fi

# ============================================================================
# Verify splash status was learned
# ============================================================================

test_start "digiKam splash status learned"
local splash_status
splash_status=$(db_get_test_app_field "org.kde.digikam" "has_splash_window")
if [[ "$splash_status" == "true" ]]; then
    local splash_ms
    splash_ms=$(db_get_test_app_field "org.kde.digikam" "splash_duration_ms")
    if [[ "$splash_ms" -gt 0 ]]; then
        test_pass
        echo "    Splash detected: duration=${splash_ms}ms"
    else
        test_fail "has_splash_window=true but splash_duration_ms=0"
    fi
elif [[ "$splash_status" == "false" ]]; then
    test_pass
    echo "    No splash detected (app may not have splash in this environment)"
else
    test_fail "Unexpected splash status: '$splash_status' (expected 'true' or 'false')"
fi

# ============================================================================
# Verify window on correct desktop
# ============================================================================

test_start "digiKam window on desktop 7"
local uuid
uuid=$(get_test_window_uuid "test-digikam-main")
if [[ -n "$uuid" ]]; then
    sleep 0.5
    assert_window_on_desktop "$uuid" 7 && test_pass || true
else
    test_skip "No UUID to check"
fi

# ============================================================================
# Close workspace
# ============================================================================

test_start "digiKam workspace close"
run_kdoitall "workspace close test-splash-digikam"
if assert_success; then
    local remaining
    remaining=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-digikam-main';")
    if [[ "$remaining" -eq 0 ]]; then
        test_pass
    else
        test_fail "app_windows row still exists after close"
    fi
fi

sleep 2
TEST_WINDOW_UUIDS=()

# ============================================================================
# Second open — with known splash data
# ============================================================================

test_start "digiKam second open (known splash data)"
run_kdoitall "workspace open --skip test-splash-digikam"
if assert_success; then
    local uuid
    uuid=$(get_test_window_uuid "test-digikam-main")
    if [[ -n "$uuid" ]]; then
        track_test_window "$uuid"
        if retry 15 1 assert_window_exists "$uuid"; then
            test_pass
        else
            test_fail "Window $uuid not found on second open"
        fi
    else
        test_fail "No UUID on second open"
    fi
fi

# ============================================================================
# Cleanup
# ============================================================================

run_kdoitall "workspace close test-splash-digikam" >/dev/null 2>&1
sleep 2
TEST_WINDOW_UUIDS=()

}
_run_test_15
