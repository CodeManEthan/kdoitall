#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 13: Complex multi-window workspace (4 windows, 4 desktops, 2 screens)

_run_test_13() {

print_section_header "Test 13: Complex Multi-Window Workspace"

# Setup apps
setup_test_app "org.mozilla.firefox" "multi" "org.mozilla.firefox"
setup_test_app "code" "unique" ""

# ============================================================================
# Create complex workspace
# ============================================================================

test_start "complex workspace create"
run_kdoitall "workspace create test-complex --from-file $FIXTURES_DIR/complex-workspace.json"
if assert_success; then
    local win_count
    win_count=$(db_test_query "SELECT COUNT(*) FROM window_definitions WHERE workspace_name='test-complex';")
    if [[ "$win_count" -eq 4 ]]; then
        test_pass
    else
        test_fail "Expected 4 window_definitions, got $win_count"
    fi
fi

# ============================================================================
# Open complex workspace
# ============================================================================

test_start "complex workspace open (4 windows)"
run_kdoitall "workspace open --skip test-complex"
if assert_success; then
    local kate_uuid dolphin_uuid firefox_uuid vscode_uuid
    kate_uuid=$(get_test_window_uuid "test-cx-kate")
    dolphin_uuid=$(get_test_window_uuid "test-cx-dolphin")
    firefox_uuid=$(get_test_window_uuid "test-cx-firefox")
    vscode_uuid=$(get_test_window_uuid "test-cx-vscode")

    local all_found=true
    for name in kate dolphin firefox vscode; do
        local var_name="${name}_uuid"
        local uuid="${!var_name}"
        if [[ -z "$uuid" ]]; then
            all_found=false
        else
            track_test_window "$uuid"
        fi
    done

    if [[ "$all_found" == "true" ]]; then
        local aw_count
        aw_count=$(db_count_test_windows "test-complex")
        if [[ "$aw_count" -eq 4 ]]; then
            test_pass
        else
            test_fail "Expected 4 app_windows rows, got $aw_count"
        fi
    else
        test_fail "Missing UUIDs: kate=$kate_uuid, dolphin=$dolphin_uuid, firefox=$firefox_uuid, vscode=$vscode_uuid"
    fi
else
    test_fail "workspace open failed"
    # Cleanup and bail
    run_kdoitall "workspace close test-complex" >/dev/null 2>&1
    sleep 1
    TEST_WINDOW_UUIDS=()
    return 0
fi

# ============================================================================
# Verify Kate: desktop 5, screen 1, Left Half
# ============================================================================

test_start "Kate on desktop 5 / screen 1 / Left Half"
local kate_uuid
kate_uuid=$(get_test_window_uuid "test-cx-kate")
if [[ -n "$kate_uuid" ]] && assert_window_exists "$kate_uuid"; then
    local kate_ok=true
    if ! assert_window_on_desktop "$kate_uuid" 5; then
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
else
    test_fail "Kate window not found"
fi

# ============================================================================
# Verify Dolphin: desktop 6, screen 1, Right Half
# ============================================================================

test_start "Dolphin on desktop 6 / screen 1 / Right Half"
local dolphin_uuid
dolphin_uuid=$(get_test_window_uuid "test-cx-dolphin")
if [[ -n "$dolphin_uuid" ]] && assert_window_exists "$dolphin_uuid"; then
    local dolphin_ok=true
    if ! assert_window_on_desktop "$dolphin_uuid" 6; then
        dolphin_ok=false
    fi
    if [[ "$dolphin_ok" == "true" ]]; then
        sleep 0.3
        local geom win_x
        geom=$(kdotool getwindowgeometry "$dolphin_uuid" 2>/dev/null)
        win_x=$(echo "$geom" | grep -oP 'Position:\s*\K-?[0-9]+(?=,)')
        if [[ "$win_x" -ge 900 ]]; then
            test_pass
        else
            test_fail "Dolphin x=$win_x, expected >= 900 for Right Half"
        fi
    fi
else
    test_fail "Dolphin window not found"
fi

# ============================================================================
# Verify Firefox: desktop 7, screen 1, Fullscreen
# ============================================================================

test_start "Firefox on desktop 7 / screen 1 / Fullscreen"
local firefox_uuid
firefox_uuid=$(get_test_window_uuid "test-cx-firefox")
if [[ -n "$firefox_uuid" ]] && assert_window_exists "$firefox_uuid"; then
    local ff_ok=true
    if ! assert_window_on_desktop "$firefox_uuid" 7; then
        ff_ok=false
    fi
    if [[ "$ff_ok" == "true" ]]; then
        sleep 0.3
        local geom win_w
        geom=$(kdotool getwindowgeometry "$firefox_uuid" 2>/dev/null)
        win_w=$(echo "$geom" | grep -oP 'Geometry:\s*\K[0-9]+(?=x)')
        if [[ "$win_w" -ge 1800 ]]; then
            test_pass
        else
            test_fail "Firefox width $win_w, expected >= 1800 for Fullscreen"
        fi
    fi
else
    test_fail "Firefox window not found"
fi

# ============================================================================
# Verify VS Code: desktop 8, screen 2, Fullscreen
# ============================================================================

test_start "VS Code on desktop 8 / screen 2 / Fullscreen"
local vscode_uuid
vscode_uuid=$(get_test_window_uuid "test-cx-vscode")
if [[ -n "$vscode_uuid" ]] && retry 10 1 assert_window_exists "$vscode_uuid"; then
    local vsc_ok=true
    if ! assert_window_on_desktop "$vscode_uuid" 8; then
        vsc_ok=false
    fi
    if [[ "$vsc_ok" == "true" ]]; then
        sleep 0.3
        local geom win_x
        geom=$(kdotool getwindowgeometry "$vscode_uuid" 2>/dev/null)
        win_x=$(echo "$geom" | grep -oP 'Position:\s*\K-?[0-9]+(?=,)')
        if [[ "$win_x" -ge 1900 ]]; then
            test_pass
        else
            test_fail "VS Code x=$win_x, expected >= 1900 for screen 2"
        fi
    fi
else
    test_fail "VS Code window not found"
fi

# ============================================================================
# Verify focus window is Firefox
# ============================================================================

test_start "focus window is Firefox (test-cx-firefox)"
local firefox_uuid
firefox_uuid=$(get_test_window_uuid "test-cx-firefox")
if [[ -n "$firefox_uuid" ]]; then
    local focus_ok=false
    local attempt
    for attempt in $(seq 1 5); do
        sleep 0.5
        local active
        active=$(kdotool getactivewindow 2>/dev/null)
        if [[ "$active" == "$firefox_uuid" ]]; then
            focus_ok=true
            break
        fi
    done
    if [[ "$focus_ok" == "true" ]]; then
        test_pass
    else
        local actual
        actual=$(kdotool getactivewindow 2>/dev/null)
        test_fail "Active window is $actual, expected $firefox_uuid"
    fi
else
    test_skip "No Firefox UUID"
fi

# ============================================================================
# Window list shows all 4 windows
# ============================================================================

test_start "window list shows all 4 windows"
run_kdoitall "window list test-complex"
if assert_success; then
    if assert_output_contains "test-cx-kate" && \
       assert_output_contains "test-cx-dolphin" && \
       assert_output_contains "test-cx-firefox" && \
       assert_output_contains "test-cx-vscode"; then
        test_pass
    fi
fi

# ============================================================================
# Export roundtrip
# ============================================================================

test_start "complex workspace export roundtrip"
local export1 export2 reimport_tmp
export1=$(mktemp /tmp/test-complex-export1-XXXXXX.json)
export2=$(mktemp /tmp/test-complex-export2-XXXXXX.json)
reimport_tmp=$(mktemp /tmp/test-complex-reimport-XXXXXX.json)

# Close workspace before export roundtrip (replace requires inactive)
run_kdoitall "workspace close test-complex" >/dev/null 2>&1
sleep 2
TEST_WINDOW_UUIDS=()

# Export
run_kdoitall "workspace export test-complex"
if assert_success; then
    echo "$CMD_OUTPUT" > "$export1"

    # Delete and re-import
    echo "y" | $KDOITALL --info workspace delete test-complex >/dev/null 2>&1
    run_kdoitall "workspace create test-complex --from-file $export1"
    if assert_success; then
        # Export again
        run_kdoitall "workspace export test-complex"
        if assert_success; then
            echo "$CMD_OUTPUT" > "$export2"
            if diff -q "$export1" "$export2" >/dev/null 2>&1; then
                test_pass
            else
                test_fail "Export roundtrip mismatch"
            fi
        fi
    fi
fi

rm -f "$export1" "$export2" "$reimport_tmp"

# ============================================================================
# Close complex workspace (if still open)
# ============================================================================

test_start "complex workspace close"
local is_active
is_active=$(db_test_query "SELECT is_active FROM workspace_definitions WHERE workspace_name='test-complex';")
if [[ "$is_active" == "1" ]]; then
    run_kdoitall "workspace close test-complex"
    if assert_success; then
        local remaining
        remaining=$(db_count_test_windows "test-complex")
        if [[ "$remaining" -eq 0 ]]; then
            test_pass
        else
            test_fail "$remaining app_windows rows remain"
        fi
    fi
else
    # Already closed during export roundtrip
    test_pass
fi

sleep 1
TEST_WINDOW_UUIDS=()

}
_run_test_13
