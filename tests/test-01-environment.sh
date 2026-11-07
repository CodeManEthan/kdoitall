#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Test 01: Environment checks

_run_test_01() {

print_section_header "Test 01: Environment Checks"

# ---- kdoitall binary exists and is executable ----

test_start "kdoitall binary exists"
if [[ -x "$KDOITALL" ]]; then
    test_pass
else
    test_fail "$KDOITALL not found or not executable"
    gate_failed
fi

# ---- Core dependencies ----

local dep
for dep in kdotool sqlite3 python3 jq kscreen-doctor gtk-launch; do
    test_start "Dependency: $dep"
    if command -v "$dep" &>/dev/null; then
        test_pass
    else
        test_fail "$dep not found in PATH"
        gate_failed
    fi
done

# ---- Database file exists ----

test_start "Database file exists"
if [[ -f "$DB_PATH" ]]; then
    test_pass
else
    test_fail "$DB_PATH not found"
    gate_failed
fi

# ---- kdoitall --help works ----

test_start "kdoitall --help"
run_kdoitall_raw "--help"
if assert_exit_code 0; then
    assert_output_contains "USAGE" && test_pass || true
fi

# ---- kdoitall --version works ----

test_start "kdoitall --version"
run_kdoitall_raw "--version"
if assert_exit_code 0; then
    assert_output_contains "kdoitall" && test_pass || true
fi

# ---- Kate .desktop file available ----

test_start "Kate application installed"
if gtk-launch --list 2>/dev/null | grep -q "org.kde.kate" || \
   [[ -f "/usr/share/applications/org.kde.kate.desktop" ]] || \
   [[ -f "$HOME/.local/share/applications/org.kde.kate.desktop" ]]; then
    test_pass
else
    test_fail "org.kde.kate.desktop not found"
    gate_failed
fi

# ---- Dolphin .desktop file available ----

test_start "Dolphin application installed"
if gtk-launch --list 2>/dev/null | grep -q "org.kde.dolphin" || \
   [[ -f "/usr/share/applications/org.kde.dolphin.desktop" ]] || \
   [[ -f "$HOME/.local/share/applications/org.kde.dolphin.desktop" ]]; then
    test_pass
else
    test_fail "org.kde.dolphin.desktop not found"
    gate_failed
fi

# ---- Enough virtual desktops (need at least 9) ----

test_start "At least 9 virtual desktops configured"
local desktop_count
desktop_count=$(kdotool get_num_desktops 2>/dev/null || echo "0")
if [[ "$desktop_count" -ge 9 ]]; then
    test_pass
else
    test_fail "Only $desktop_count desktops (need >= 9)"
    gate_failed
fi

}
_run_test_01
