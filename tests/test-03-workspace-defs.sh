#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 3: Workspace definition CRUD (no live windows)

_run_test_03() {

print_section_header "Phase 3: Workspace Definitions"

# ============================================================================
# workspace create --from-file
# ============================================================================

test_start "workspace create --from-file (single-kate)"
run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate.json"
if assert_success; then
    if assert_db_row_exists "workspace_definitions" "workspace_name='test-single-kate'"; then
        if assert_db_row_exists "window_definitions" "window_name='test-kate-main' AND workspace_name='test-single-kate'"; then
            if assert_file_exists "$WORKSPACE_SCRIPTS_DIR/test-single-kate.sh"; then
                test_pass
            fi
        fi
    fi
fi

# ---- Verify window definition details ----

test_start "window definition has correct desktop/screen/position"
local wd_desktop wd_screen wd_position
wd_desktop=$(db_test_query "SELECT desktop FROM window_definitions WHERE window_name='test-kate-main';")
wd_screen=$(db_test_query "SELECT screen FROM window_definitions WHERE window_name='test-kate-main';")
wd_position=$(db_test_query "SELECT position FROM window_definitions WHERE window_name='test-kate-main';")
if [[ "$wd_desktop" == "9" && -n "$wd_screen" && -n "$wd_position" ]]; then
    test_pass
else
    test_fail "desktop=$wd_desktop screen=$wd_screen position=$wd_position"
fi

# ============================================================================
# workspace list
# ============================================================================

test_start "workspace list"
run_kdoitall "workspace list"
if assert_success; then
    assert_output_contains "test-single-kate" && test_pass || true
fi

test_start "workspace list --details"
run_kdoitall "workspace list --details"
if assert_success; then
    assert_output_contains "test-single-kate" && test_pass || true
fi

# ============================================================================
# workspace info
# ============================================================================

test_start "workspace info"
run_kdoitall "workspace info test-single-kate"
if assert_success; then
    if assert_output_contains "test-single-kate"; then
        assert_output_contains "test-kate-main" && test_pass || true
    fi
fi

# ============================================================================
# workspace export
# ============================================================================

test_start "workspace export"
run_kdoitall "workspace export test-single-kate"
if assert_success; then
    if echo "$CMD_OUTPUT" | jq empty 2>/dev/null; then
        local export_ws export_win_name
        export_ws=$(echo "$CMD_OUTPUT" | jq -r '.workspace')
        export_win_name=$(echo "$CMD_OUTPUT" | jq -r '.windows[0].name')
        if [[ "$export_ws" == "test-single-kate" && "$export_win_name" == "test-kate-main" ]]; then
            test_pass
        else
            test_fail "Exported JSON has wrong fields: workspace=$export_ws, window=$export_win_name"
        fi
    else
        test_fail "Export output is not valid JSON"
    fi
fi

# ============================================================================
# workspace create --from-file --replace
# ============================================================================

test_start "workspace create --from-file --replace"
run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate-modified.json --replace"
if assert_success; then
    local new_desktop
    new_desktop=$(db_test_query "SELECT desktop FROM window_definitions WHERE window_name='test-kate-main';")
    if [[ "$new_desktop" == "8" ]]; then
        test_pass
    else
        test_fail "Expected desktop 8 after replace, got $new_desktop"
    fi
fi

# ============================================================================
# workspace export roundtrip
# ============================================================================

test_start "workspace export -> re-import -> export roundtrip"
run_kdoitall "workspace export test-single-kate"
local export1="$CMD_OUTPUT"

local tmpfile
tmpfile=$(mktemp /tmp/kdoitall-test-export-XXXXXX.json)
echo "$export1" > "$tmpfile"

run_kdoitall "workspace create test-single-kate --from-file $tmpfile --replace"
if assert_success; then
    run_kdoitall "workspace export test-single-kate"
    local export2="$CMD_OUTPUT"

    local norm1 norm2
    norm1=$(echo "$export1" | jq -S '.')
    norm2=$(echo "$export2" | jq -S '.')

    if [[ "$norm1" == "$norm2" ]]; then
        test_pass
    else
        test_fail "Roundtrip export mismatch"
    fi
fi
rm -f "$tmpfile"

# ============================================================================
# Restore original fixture before delete test
# ============================================================================

run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate.json --replace" >/dev/null 2>&1

# ============================================================================
# workspace delete
# ============================================================================

test_start "workspace create (for delete test)"
local delete_tmpfile
delete_tmpfile=$(mktemp /tmp/kdoitall-test-delete-XXXXXX.json)
cat > "$delete_tmpfile" << 'FIXTURE'
{
  "workspace": "test-delete-me",
  "description": "Workspace to test deletion",
  "windows": [
    {
      "name": "test-delete-window",
      "app": "org.kde.kate",
      "desktop": 9,
      "screen": "1",
      "position": "Fullscreen"
    }
  ]
}
FIXTURE
run_kdoitall "workspace create test-delete-me --from-file $delete_tmpfile"
if assert_success; then
    test_pass
else
    test_fail "Could not create workspace for delete test"
fi
rm -f "$delete_tmpfile"

test_start "workspace delete (with confirmation)"
echo "y" | $KDOITALL --info workspace delete test-delete-me >/dev/null 2>&1
local delete_exit=$?
if [[ "$delete_exit" -eq 0 ]]; then
    local ws_count win_count
    ws_count=$(db_test_query "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name='test-delete-me';")
    win_count=$(db_test_query "SELECT COUNT(*) FROM window_definitions WHERE workspace_name='test-delete-me';")
    if [[ "$ws_count" -eq 0 && "$win_count" -eq 0 ]]; then
        if [[ ! -f "$WORKSPACE_SCRIPTS_DIR/test-delete-me.sh" ]]; then
            test_pass
        else
            test_fail "Script file still exists after delete"
        fi
    else
        test_fail "DB rows remain: workspace=$ws_count, windows=$win_count"
    fi
else
    test_fail "Delete command failed with exit code $delete_exit"
fi

# ---- workspace create duplicate without --replace should fail ----

test_start "workspace create duplicate without --replace"
run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate.json"
assert_failure && test_pass || true

# ============================================================================
# status command (no active workspaces)
# ============================================================================

test_start "status command (no active workspaces)"
run_kdoitall "status"
assert_success && test_pass || true

}
_run_test_03
