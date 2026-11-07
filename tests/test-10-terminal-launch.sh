#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 10: Terminal launch functions (VS Code + Firefox)

_run_test_10() {

print_section_header "Test 10: Terminal Launch Functions"

# Setup: ensure apps are registered with safe mode skipped
setup_test_app "code" "unique" ""
setup_test_app "org.mozilla.firefox" "multi" "org.mozilla.firefox"

# ============================================================================
# VS Code terminal launch — create workspace
# ============================================================================

test_start "VS Code terminal workspace create"
run_kdoitall "workspace create test-terminal-vscode --from-file $FIXTURES_DIR/terminal-vscode.json"
if assert_success; then
    local fn
    fn=$(db_test_query "SELECT launch_function FROM window_definitions WHERE window_name='test-vscode-main';")
    local params
    params=$(db_test_query "SELECT parameters FROM window_definitions WHERE window_name='test-vscode-main';")
    if [[ "$fn" == "launch_code_window" && "$params" == "/tmp" ]]; then
        test_pass
    else
        test_fail "launch_function='$fn' params='$params', expected 'launch_code_window' '/tmp'"
    fi
fi

# ============================================================================
# VS Code terminal launch — open workspace
# ============================================================================

test_start "VS Code terminal workspace open"
run_kdoitall "workspace open --skip test-terminal-vscode"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-terminal-vscode';")
    if [[ "$is_active" != "1" ]]; then
        test_fail "is_active=$is_active, expected 1"
    else
        local uuid
        uuid=$(get_test_window_uuid "test-vscode-main")
        if [[ -z "$uuid" ]]; then
            test_fail "No app_windows row for test-vscode-main"
        else
            track_test_window "$uuid"
            if retry 10 1 assert_window_exists "$uuid"; then
                test_pass
            else
                test_fail "Window $uuid not found via kdotool"
            fi
        fi
    fi
else
    test_fail "workspace open failed"
fi

# ============================================================================
# VS Code window on correct desktop
# ============================================================================

test_start "VS Code window on desktop 7"
local uuid
uuid=$(get_test_window_uuid "test-vscode-main")
if [[ -n "$uuid" ]]; then
    sleep 0.5
    assert_window_on_desktop "$uuid" 7 && test_pass || true
else
    test_skip "No UUID to check"
fi

# ============================================================================
# VS Code workspace close
# ============================================================================

test_start "VS Code terminal workspace close"
run_kdoitall "workspace close test-terminal-vscode"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-terminal-vscode';")
    if [[ "$is_active" != "0" ]]; then
        test_fail "is_active=$is_active after close, expected 0"
    else
        local remaining
        remaining=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-vscode-main';")
        if [[ "$remaining" -ne 0 ]]; then
            test_fail "app_windows row still exists after close"
        else
            test_pass
        fi
    fi
fi

sleep 1
TEST_WINDOW_UUIDS=()

# ============================================================================
# Firefox terminal launch — create workspace
# ============================================================================

test_start "Firefox terminal workspace create"
run_kdoitall "workspace create test-terminal-firefox --from-file $FIXTURES_DIR/terminal-firefox.json"
if assert_success; then
    local fn
    fn=$(db_test_query "SELECT launch_function FROM window_definitions WHERE window_name='test-firefox-main';")
    if [[ "$fn" == "launch_firefox_window" ]]; then
        test_pass
    else
        test_fail "launch_function='$fn', expected 'launch_firefox_window'"
    fi
fi

# ============================================================================
# Firefox terminal launch — open workspace
# ============================================================================

test_start "Firefox terminal workspace open"
run_kdoitall "workspace open --skip test-terminal-firefox"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-terminal-firefox';")
    if [[ "$is_active" != "1" ]]; then
        test_fail "is_active=$is_active, expected 1"
    else
        local uuid
        uuid=$(get_test_window_uuid "test-firefox-main")
        if [[ -z "$uuid" ]]; then
            test_fail "No app_windows row for test-firefox-main"
        else
            track_test_window "$uuid"
            if retry 5 1 assert_window_exists "$uuid"; then
                local win_class
                win_class=$(db_test_query "SELECT class FROM app_windows WHERE window_name='test-firefox-main';")
                if [[ "$win_class" == "org.mozilla.firefox" ]]; then
                    test_pass
                else
                    test_fail "Window class is '$win_class', expected 'org.mozilla.firefox'"
                fi
            else
                test_fail "Window $uuid not found via kdotool"
            fi
        fi
    fi
fi

# ============================================================================
# Firefox window on correct desktop
# ============================================================================

test_start "Firefox window on desktop 8"
local uuid
uuid=$(get_test_window_uuid "test-firefox-main")
if [[ -n "$uuid" ]]; then
    sleep 0.5
    assert_window_on_desktop "$uuid" 8 && test_pass || true
else
    test_skip "No UUID to check"
fi

# ============================================================================
# Firefox workspace close
# ============================================================================

test_start "Firefox terminal workspace close"
run_kdoitall "workspace close test-terminal-firefox"
if assert_success; then
    local is_active
    is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-terminal-firefox';")
    if [[ "$is_active" != "0" ]]; then
        test_fail "is_active=$is_active after close, expected 0"
    else
        local remaining
        remaining=$(db_test_query "SELECT COUNT(*) FROM app_windows WHERE window_name='test-firefox-main';")
        if [[ "$remaining" -ne 0 ]]; then
            test_fail "app_windows row still exists after close"
        else
            test_pass
        fi
    fi
fi

sleep 1
TEST_WINDOW_UUIDS=()

}
_run_test_10
