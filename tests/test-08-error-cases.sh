#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test Phase 8: Error handling and edge cases

_run_test_08() {

print_section_header "Phase 8: Error Cases"

# ============================================================================
# Invalid workspace operations
# ============================================================================

test_start "workspace open nonexistent workspace"
run_kdoitall "workspace open --skip nonexistent-workspace-xyz"
assert_failure && test_pass || true

test_start "workspace close nonexistent workspace"
run_kdoitall "workspace close nonexistent-workspace-xyz"
assert_failure && test_pass || true

test_start "workspace info nonexistent workspace"
run_kdoitall "workspace info nonexistent-workspace-xyz"
assert_failure && test_pass || true

test_start "workspace focus nonexistent workspace"
run_kdoitall "workspace focus nonexistent-workspace-xyz"
assert_failure && test_pass || true

test_start "workspace minimize nonexistent workspace"
run_kdoitall "workspace minimize nonexistent-workspace-xyz"
assert_failure && test_pass || true

test_start "workspace export nonexistent workspace"
run_kdoitall "workspace export nonexistent-workspace-xyz"
assert_failure && test_pass || true

# ============================================================================
# Missing arguments
# ============================================================================

test_start "workspace open with no name"
run_kdoitall "workspace open"
assert_failure && test_pass || true

test_start "workspace close with no name"
run_kdoitall "workspace close"
assert_failure && test_pass || true

test_start "window status with no name"
run_kdoitall "window status"
assert_failure && test_pass || true

test_start "window move with no name"
run_kdoitall "window move"
assert_failure && test_pass || true

# ============================================================================
# Invalid window operations
# ============================================================================

test_start "window status nonexistent window"
run_kdoitall "window status nonexistent-window-xyz"
assert_failure && test_pass || true

test_start "window focus nonexistent window"
run_kdoitall "window focus nonexistent-window-xyz"
assert_failure && test_pass || true

test_start "window move nonexistent window"
run_kdoitall "window move nonexistent-window-xyz -d 1"
assert_failure && test_pass || true

test_start "window close nonexistent window"
run_kdoitall "window close nonexistent-window-xyz"
assert_failure && test_pass || true

test_start "window open nonexistent window"
run_kdoitall "window open nonexistent-window-xyz"
assert_failure && test_pass || true

# ============================================================================
# Invalid config file
# ============================================================================

test_start "workspace create --from-file with nonexistent app"
run_kdoitall "workspace create test-invalid --from-file $FIXTURES_DIR/invalid-app.json"
assert_failure && test_pass || true

test_start "workspace create --from-file with missing file"
run_kdoitall "workspace create test-invalid --from-file /tmp/nonexistent-file-xyz.json"
assert_failure && test_pass || true

local bad_json
bad_json=$(mktemp /tmp/kdoitall-test-bad-json-XXXXXX.json)
echo "{ this is not valid json" > "$bad_json"

test_start "workspace create --from-file with malformed JSON"
run_kdoitall "workspace create test-invalid --from-file $bad_json"
assert_failure && test_pass || true
rm -f "$bad_json"

# ============================================================================
# Invalid window move targets
# ============================================================================

if ! db_test_query "SELECT COUNT(*) FROM workspace_definitions WHERE workspace_name='test-single-kate';" | grep -q "^1$"; then
    run_kdoitall "workspace create test-single-kate --from-file $FIXTURES_DIR/single-kate.json" >/dev/null 2>&1
fi
run_kdoitall "workspace open --skip test-single-kate" >/dev/null 2>&1
local err_uuid
err_uuid=$(get_test_window_uuid "test-kate-main")

if [[ -n "$err_uuid" ]]; then
    track_test_window "$err_uuid"

    test_start "window move invalid desktop (99)"
    run_kdoitall "window move test-kate-main -d 99"
    assert_failure && test_pass || true

    test_start "window move invalid position"
    run_kdoitall "window move test-kate-main -p 'Invalid Position XYZ'"
    assert_failure && test_pass || true

    test_start "window move invalid screen reference"
    run_kdoitall "window move test-kate-main -s 99"
    assert_failure && test_pass || true

    # Cleanup
    run_kdoitall "workspace close test-single-kate" >/dev/null 2>&1
    sleep 1
    TEST_WINDOW_UUIDS=()
else
    test_start "window move invalid desktop (99)"
    test_skip "No window available for move error tests"
    test_start "window move invalid position"
    test_skip "No window available for move error tests"
    test_start "window move invalid screen reference"
    test_skip "No window available for move error tests"
fi

# ============================================================================
# workspace close inactive workspace
# ============================================================================

test_start "workspace close inactive workspace"
run_kdoitall "workspace close test-single-kate"
assert_failure && test_pass || true

# ============================================================================
# workspace focus inactive workspace
# ============================================================================

test_start "workspace focus inactive workspace"
run_kdoitall "workspace focus test-single-kate"
assert_failure && test_pass || true

# ============================================================================
# Unsafe values are refused at every entry point
# ============================================================================
# Params may hold tabs but not '|', newlines or other control characters, and
# a launch function name is matched exactly, never as a pattern. A refused
# command leaves no window definition behind and runs nothing.

local unsafe_marker unsafe_json
unsafe_marker=$(mktemp -u /tmp/kdoitall-test-unsafe-marker-XXXXXX)
unsafe_json=$(mktemp /tmp/kdoitall-test-unsafe-XXXXXX.json)

# import: '|' in params
jq -n '{windows: [{name: "test-unsafe-win", app: "org.kde.kate", desktop: 1,
        screen: "1", position: "Fullscreen", params: "a|b"}]}' > "$unsafe_json"
test_start "import refuses '|' in params"
run_kdoitall "workspace create test-unsafe --from-file $(printf '%q' "$unsafe_json")"
assert_failure && test_pass || true

# import: newline in params
jq -n '{windows: [{name: "test-unsafe-win", app: "org.kde.kate", desktop: 1,
        screen: "1", position: "Fullscreen", params: "a\nb"}]}' > "$unsafe_json"
test_start "import refuses a newline in params"
run_kdoitall "workspace create test-unsafe --from-file $(printf '%q' "$unsafe_json")"
assert_failure && test_pass || true

# import: a launch function name that a grep pattern would have matched
jq -n --arg fn "\$(touch $unsafe_marker)\\|" \
    '{windows: [{name: "test-unsafe-win", app: "code", desktop: 1,
        screen: "1", position: "Fullscreen", function: $fn, params: "/tmp"}]}' > "$unsafe_json"
test_start "import refuses a launch function that is not an exact match"
run_kdoitall "workspace create test-unsafe --from-file $(printf '%q' "$unsafe_json")"
assert_failure && test_pass || true
rm -f "$unsafe_json"

# add-window: '|' in --params
test_start "add-window refuses '|' in --params"
run_kdoitall "workspace add-window test-single-kate --name test-unsafe-win --app org.kde.kate -d 1 -s 1 -p fs --params $(printf '%q' 'a|b')"
assert_failure && test_pass || true

# add-window: crafted --function
test_start "add-window refuses a launch function that is not an exact match"
run_kdoitall "workspace add-window test-single-kate --name test-unsafe-win --app code -d 1 -s 1 -p fs -f $(printf '%q' "\$(touch $unsafe_marker)\\|") --params /tmp"
assert_failure && test_pass || true

# edit-window: '|' in --params
test_start "edit-window refuses '|' in --params"
run_kdoitall "workspace edit-window test-single-kate test-kate-main --params $(printf '%q' 'a|b')"
assert_failure && test_pass || true

# edit-window: crafted --function
test_start "edit-window refuses a launch function that is not an exact match"
run_kdoitall "workspace edit-window test-single-kate test-kate-main -f $(printf '%q' "\$(touch $unsafe_marker)\\|")"
assert_failure && test_pass || true

test_start "refused commands left no window definition and ran nothing"
local unsafe_rows
unsafe_rows=$(db_test_query "SELECT COUNT(*) FROM window_definitions WHERE window_name='test-unsafe-win' OR workspace_name='test-unsafe';")
if [[ "$unsafe_rows" != "0" ]]; then
    test_fail "found $unsafe_rows window definition(s) from a refused command"
elif [[ -e "$unsafe_marker" ]]; then
    test_fail "a crafted value was run by the shell ($unsafe_marker exists)"
    rm -f "$unsafe_marker"
else
    test_pass
fi

# ============================================================================
# Invalid subcommands
# ============================================================================

test_start "workspace invalid subcommand"
run_kdoitall "workspace invalid-subcommand-xyz"
assert_failure && test_pass || true

test_start "window invalid subcommand"
run_kdoitall "window invalid-subcommand-xyz"
assert_failure && test_pass || true

test_start "app invalid subcommand"
run_kdoitall "app invalid-subcommand-xyz"
assert_failure && test_pass || true

}
_run_test_08
