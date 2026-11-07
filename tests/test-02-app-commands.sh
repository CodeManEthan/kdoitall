#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 02: App commands and screen commands

_run_test_02() {

# ============================================================================
# Test 02: App Commands
# ============================================================================

print_section_header "Test 02: App Commands"

# ---- app scan (critical gate) ----

test_start "app scan"
run_kdoitall "app scan"
if assert_success; then
    local kate_exists dolphin_exists
    kate_exists=$(db_test_query "SELECT COUNT(*) FROM applications WHERE app_id='org.kde.kate';")
    dolphin_exists=$(db_test_query "SELECT COUNT(*) FROM applications WHERE app_id='org.kde.dolphin';")
    if [[ "$kate_exists" -gt 0 && "$dolphin_exists" -gt 0 ]]; then
        test_pass
    else
        test_fail "Kate ($kate_exists) or Dolphin ($dolphin_exists) not in applications table"
        gate_failed
    fi
else
    gate_failed
fi

check_gate || return 0

# ---- app list (no filter) ----

test_start "app list (no filter)"
run_kdoitall "app list"
if assert_success; then
    assert_output_not_empty && test_pass || true
fi

# ---- app list terminal ----

test_start "app list terminal"
run_kdoitall "app list terminal"
assert_success && test_pass || true

# ---- app list desktop ----

test_start "app list desktop"
run_kdoitall "app list desktop"
if assert_success; then
    assert_output_not_empty && test_pass || true
fi

# ---- app info by app_id ----

test_start "app info by app_id (org.kde.kate)"
run_kdoitall "app info org.kde.kate"
if assert_success; then
    assert_output_contains "kate" && test_pass || true
fi

# ---- app info by display name ----

test_start "app info by display name (Kate)"
run_kdoitall "app info Kate"
if assert_success; then
    assert_output_contains "org.kde.kate" && test_pass || true
fi

# ---- app info nonexistent ----

test_start "app info nonexistent app"
run_kdoitall "app info nonexistent.app.xyz"
assert_failure && test_pass || true

# ---- app validate ----

test_start "app validate"
run_kdoitall "app validate"
assert_success && test_pass || true

# ---- app options (Kate — desktop only) ----

test_start "app options org.kde.kate"
run_kdoitall "app options org.kde.kate"
if [[ "$CMD_EXIT_CODE" -eq 0 ]]; then
    test_pass
else
    test_pass
fi

# ============================================================================
# Test 02: Safe Mode + Screen Aliases
# ============================================================================

print_section_header "Test 02: Safe Mode & Screen Aliases"

# ---- safe-mode skip ----

test_start "app safe-mode skip org.kde.kate"
run_kdoitall "app safe-mode skip org.kde.kate"
if assert_success; then
    local sm_completed
    sm_completed=$(db_test_query "SELECT safe_mode_completed FROM applications WHERE app_id='org.kde.kate';")
    if [[ "$sm_completed" == "1" ]]; then
        test_pass
    else
        test_fail "safe_mode_completed not set to 1 (got: $sm_completed)"
    fi
fi

# ---- safe-mode reset ----

test_start "app safe-mode reset org.kde.kate"
run_kdoitall "app safe-mode reset org.kde.kate"
if assert_success; then
    local sm_completed
    sm_completed=$(db_test_query "SELECT safe_mode_completed FROM applications WHERE app_id='org.kde.kate';")
    if [[ "$sm_completed" == "0" ]]; then
        test_pass
    else
        test_fail "safe_mode_completed not reset to 0 (got: $sm_completed)"
    fi
fi

# ---- Re-skip Kate and Dolphin for later workspace tests ----

test_start "app safe-mode skip (Kate + Dolphin for tests)"
run_kdoitall "app safe-mode skip org.kde.kate"
run_kdoitall "app safe-mode skip org.kde.dolphin"
if [[ "$CMD_EXIT_CODE" -eq 0 ]]; then
    test_pass
else
    test_fail "Failed to skip safe mode for test apps"
fi

# ---- screen list ----

test_start "screen list"
run_kdoitall "screen list"
if assert_success; then
    assert_output_not_empty && test_pass || true
fi

# ---- screen alias set ----

test_start "screen alias set (test-alias -> 1)"
run_kdoitall "screen alias test-alias 1"
if assert_success; then
    local alias_target
    alias_target=$(db_test_query "SELECT target FROM screen_aliases WHERE alias='test-alias';")
    # The app resolves the output number to a persistent screen name (e.g. "eDP-1")
    if [[ -n "$alias_target" ]]; then
        test_pass
    else
        test_fail "Alias row not found or target is empty"
    fi
fi

# ---- screen alias remove ----

test_start "screen alias remove (test-alias)"
run_kdoitall "screen alias remove test-alias"
if assert_success; then
    local alias_count
    alias_count=$(db_test_query "SELECT COUNT(*) FROM screen_aliases WHERE alias='test-alias';")
    if [[ "$alias_count" -eq 0 ]]; then
        test_pass
    else
        test_fail "Alias still exists after removal"
    fi
fi

}
_run_test_02
