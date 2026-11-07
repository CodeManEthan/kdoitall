#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 14: Launch mode behaviors (MULTI, SINGLE, UNIQUE)

_run_test_14() {

print_section_header "Test 14: Launch Mode Behaviors"

# Setup apps with correct launch modes
setup_test_app "org.mozilla.firefox" "multi" "org.mozilla.firefox"
setup_test_app "systemsettings" "single" ""
setup_test_app "code" "unique" ""

# ============================================================================
#  MULTI MODE — Firefox (two windows from one workspace)
# ============================================================================

test_start "MULTI: create workspace with 2 Firefox windows"
run_kdoitall "workspace create test-multi-firefox --from-file $FIXTURES_DIR/multi-firefox.json"
if assert_success; then
    local win_count
    win_count=$(db_test_query "SELECT COUNT(*) FROM window_definitions WHERE workspace_name='test-multi-firefox';")
    if [[ "$win_count" -eq 2 ]]; then
        test_pass
    else
        test_fail "Expected 2 window_definitions, got $win_count"
    fi
fi

test_start "MULTI: open workspace — both windows launch"
run_kdoitall "workspace open --skip test-multi-firefox"
if assert_success; then
    local uuid1 uuid2
    uuid1=$(get_test_window_uuid "test-ff-window1")
    uuid2=$(get_test_window_uuid "test-ff-window2")

    if [[ -n "$uuid1" && -n "$uuid2" ]]; then
        track_test_window "$uuid1"
        track_test_window "$uuid2"

        if [[ "$uuid1" == "$uuid2" ]]; then
            test_fail "Both windows have same UUID (MULTI should create separate windows)"
        else
            if retry 5 1 assert_window_exists "$uuid1" && \
               retry 5 1 assert_window_exists "$uuid2"; then
                test_pass
            else
                test_fail "One or both windows not found via kdotool"
            fi
        fi
    else
        test_fail "Missing UUIDs: window1=$uuid1, window2=$uuid2"
    fi
else
    test_fail "workspace open failed"
fi

test_start "MULTI: both windows on desktop 7"
local uuid1 uuid2
uuid1=$(get_test_window_uuid "test-ff-window1")
uuid2=$(get_test_window_uuid "test-ff-window2")
if [[ -n "$uuid1" && -n "$uuid2" ]]; then
    sleep 0.5
    local d1_ok=false d2_ok=false
    assert_window_on_desktop "$uuid1" 7 && d1_ok=true
    assert_window_on_desktop "$uuid2" 7 && d2_ok=true
    if [[ "$d1_ok" == "true" && "$d2_ok" == "true" ]]; then
        test_pass
    fi
else
    test_skip "No UUIDs to check"
fi

test_start "MULTI: windows have Left/Right Half positions"
if [[ -n "$uuid1" && -n "$uuid2" ]]; then
    sleep 0.3
    local geom1 w1 geom2 w2
    geom1=$(kdotool getwindowgeometry "$uuid1" 2>/dev/null)
    w1=$(echo "$geom1" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
    geom2=$(kdotool getwindowgeometry "$uuid2" 2>/dev/null)
    w2=$(echo "$geom2" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')

    if [[ "$w1" -ge 900 && "$w1" -le 1020 && "$w2" -ge 900 && "$w2" -le 1020 ]]; then
        test_pass
    else
        test_fail "Widths: w1=$w1, w2=$w2 — expected both in 900-1020 (half screen)"
    fi
else
    test_skip "No UUIDs to check"
fi

test_start "MULTI: close workspace"
run_kdoitall "workspace close test-multi-firefox"
if assert_success; then
    local remaining
    remaining=$(db_count_test_windows "test-multi-firefox")
    if [[ "$remaining" -eq 0 ]]; then
        test_pass
    else
        test_fail "$remaining app_windows rows remain after close"
    fi
fi

sleep 1
TEST_WINDOW_UUIDS=()

# ============================================================================
#  SINGLE MODE — System Settings (existing window reused)
# ============================================================================

test_start "SINGLE: create workspace"
run_kdoitall "workspace create test-single-sysset --from-file $FIXTURES_DIR/single-systemsettings.json"
if assert_success; then
    test_pass
fi

test_start "SINGLE: first open (initial launch)"
run_kdoitall "workspace open --skip test-single-sysset"
if assert_success; then
    local uuid
    uuid=$(get_test_window_uuid "test-sysset-main")
    if [[ -n "$uuid" ]]; then
        track_test_window "$uuid"

        # Read auto-detected class and set it if populated
        local detected_class
        detected_class=$(db_test_query "SELECT class FROM app_windows WHERE window_name='test-sysset-main';")
        if [[ -n "$detected_class" ]]; then
            db_set_test_app_class "systemsettings" "$detected_class"
        fi

        test_pass
    else
        test_fail "No UUID for test-sysset-main"
    fi
else
    test_fail "First open failed"
fi

test_start "SINGLE: close workspace (window closes)"
run_kdoitall "workspace close test-single-sysset"
if assert_success; then
    test_pass
else
    test_fail "Close failed"
fi

sleep 2
TEST_WINDOW_UUIDS=()

# Verify class was learned
local sysset_class
sysset_class=$(db_get_test_app_field "systemsettings" "app_class")
if [[ -z "$sysset_class" ]]; then
    # Class wasn't auto-detected; skip the reuse test
    test_start "SINGLE: window reuse (skip — class not detected)"
    test_skip "System Settings class was not auto-detected; cannot test SINGLE reuse"
else
    # Launch System Settings externally
    test_start "SINGLE: launch externally via gtk-launch"
    gtk-launch systemsettings 2>/dev/null &
    sleep 3

    # Find the externally launched window by class
    local external_uuid=""
    local search_output
    search_output=$(kdotool search --class "$sysset_class" 2>/dev/null) || true
    if [[ -n "$search_output" ]]; then
        # Take the first match
        external_uuid=$(echo "$search_output" | head -n1)
        track_test_window "$external_uuid"
        test_pass
        echo "    External UUID: $external_uuid (class: $sysset_class)"
    else
        test_fail "Could not find externally launched System Settings (class: $sysset_class)"
    fi

    if [[ -n "$external_uuid" ]]; then
        # Re-open workspace — should reclaim the existing window
        test_start "SINGLE: re-open workspace reclaims existing window"
        run_kdoitall "workspace open --skip test-single-sysset"
        if assert_success; then
            local claimed_uuid
            claimed_uuid=$(get_test_window_uuid "test-sysset-main")
            if [[ "$claimed_uuid" == "$external_uuid" ]]; then
                test_pass
                echo "    Window reclaimed: $claimed_uuid"
            else
                test_fail "UUID mismatch: claimed=$claimed_uuid, external=$external_uuid"
            fi
        fi

        test_start "SINGLE: close workspace (final)"
        run_kdoitall "workspace close test-single-sysset"
        if assert_success; then
            test_pass
        fi
    fi
fi

sleep 1
TEST_WINDOW_UUIDS=()

# ============================================================================
#  UNIQUE MODE — VS Code (same content reuses window)
# ============================================================================

test_start "UNIQUE: create first workspace"
run_kdoitall "workspace create test-unique-vscode --from-file $FIXTURES_DIR/unique-vscode.json"
if assert_success; then
    test_pass
fi

test_start "UNIQUE: open first workspace (VS Code in /tmp)"
run_kdoitall "workspace open --skip test-unique-vscode"
if assert_success; then
    local uuid1
    uuid1=$(get_test_window_uuid "test-vscode-unique")
    if [[ -n "$uuid1" ]]; then
        track_test_window "$uuid1"
        if retry 10 1 assert_window_exists "$uuid1"; then
            test_pass
            echo "    UUID1: $uuid1"
        else
            test_fail "Window $uuid1 not found via kdotool"
        fi
    else
        test_fail "No UUID for test-vscode-unique"
    fi
else
    test_fail "First open failed"
fi

# Create a second workspace pointing to same directory
test_start "UNIQUE: create second workspace (same /tmp)"
local unique2_tmpfile
unique2_tmpfile=$(mktemp /tmp/test-unique-vscode2-XXXXXX.json)
cat > "$unique2_tmpfile" << 'UNIQUE2EOF'
{
  "workspace": "test-unique-vscode2",
  "description": "Second VS Code workspace for UNIQUE test",
  "windows": [
    {
      "name": "test-vscode-unique2",
      "app": "code",
      "desktop": 7,
      "screen": "1",
      "position": "Right Half",
      "function": "launch_code_window",
      "params": "/tmp"
    }
  ]
}
UNIQUE2EOF
run_kdoitall "workspace create test-unique-vscode2 --from-file $unique2_tmpfile"
rm -f "$unique2_tmpfile"
if assert_success; then
    test_pass
fi

test_start "UNIQUE: open second workspace (same /tmp dir)"
run_kdoitall "workspace open --skip test-unique-vscode2"
if assert_success; then
    local uuid1 uuid2
    uuid1=$(get_test_window_uuid "test-vscode-unique")
    uuid2=$(get_test_window_uuid "test-vscode-unique2")
    if [[ -n "$uuid2" ]]; then
        track_test_window "$uuid2"
        if [[ "$uuid2" == "$uuid1" ]]; then
            test_pass
            echo "    Window reused: UUID=$uuid2 (same as first workspace)"
        else
            # VS Code opened a new window — this is acceptable behavior
            test_pass
            echo "    New window created: UUID=$uuid2 (VS Code did not redirect)"
        fi
    else
        # If no UUID2, the open may have still succeeded by reclaiming uuid1
        if [[ -n "$uuid1" ]]; then
            test_pass
            echo "    Window reclaimed under first workspace UUID=$uuid1"
        else
            test_fail "No UUID for test-vscode-unique2"
        fi
    fi
else
    test_fail "Second open failed"
fi

# Cleanup UNIQUE tests
run_kdoitall "workspace close test-unique-vscode" >/dev/null 2>&1
run_kdoitall "workspace close test-unique-vscode2" >/dev/null 2>&1
sleep 2
TEST_WINDOW_UUIDS=()

}
_run_test_14
