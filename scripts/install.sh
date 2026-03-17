#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# --- Determine project root ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Verify we're in the right place ---
if [[ ! -f "$PROJECT_ROOT/bin/kdoitall" ]]; then
    echo "Error: Cannot find kdoitall project. Run this script from the project directory." >&2
    exit 1
fi

# --- Check bash version ---
if ((BASH_VERSINFO[0] < 4)); then
    echo "Error: Bash 4.0+ is required (found ${BASH_VERSION})" >&2
    exit 1
fi

echo "Installing kdoitall..."
echo ""

# --- Setup kdotool (auto-download if missing) ---
echo "Checking kdotool..."
source "$PROJECT_ROOT/scripts/setup-kdotool.sh"
setup_kdotool

# --- Check dependencies ---
echo "Checking dependencies..."
source "$PROJECT_ROOT/lib/utils/checks.sh"
check_dependencies

# --- Define directories ---
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kdoitall"
BIN_DIR="$HOME/.local/bin"

# --- Create directories ---
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/workspaces"
mkdir -p "$CONFIG_DIR"
mkdir -p "$BIN_DIR"

# --- Initialize database ---
SCHEMA_FILE="$PROJECT_ROOT/database/schema.sql"
DB_FILE="$DATA_DIR/kdoitall.db"

if [[ ! -f "$DB_FILE" ]]; then
    if command -v sqlite3 &> /dev/null; then
        sqlite3 "$DB_FILE" < "$SCHEMA_FILE"
        echo "✓ Initialized database: $DB_FILE"
    else
        echo "⚠ sqlite3 not found — skipping database initialization" >&2
    fi
else
    echo "✓ Database already exists: $DB_FILE"
fi

# --- Build reference database ---
REGISTRY_SEED="$PROJECT_ROOT/database/app-registry.sql"
REGISTRY_DB="$PROJECT_ROOT/database/app-registry.db"

if [[ -f "$REGISTRY_SEED" ]]; then
    if command -v sqlite3 &> /dev/null; then
        rm -f "$REGISTRY_DB"
        sqlite3 "$REGISTRY_DB" < "$REGISTRY_SEED"
        echo "✓ Built app registry database"
    else
        echo "⚠ sqlite3 not found — skipping app registry build" >&2
    fi
else
    echo "⚠ App registry seed file not found: $REGISTRY_SEED" >&2
fi

# --- Generate user config file ---
USER_CONFIG="$CONFIG_DIR/config"

# shellcheck source=config-utils.sh
source "${SCRIPT_DIR}/config-utils.sh"

if [[ ! -f "$USER_CONFIG" ]]; then
    cat > "$USER_CONFIG" << 'CONFIGEOF'
#!/bin/bash

# kdoitall user configuration
# Uncomment and modify settings to override project defaults.

# Standard .desktop file locations
# DESKTOP_FILE_LOCATIONS=(
#     "/usr/share/applications"
#     "/usr/local/share/applications"
#     "$HOME/.local/share/applications"
#     "/var/lib/flatpak/exports/share/applications"
#     "$HOME/.local/share/flatpak/exports/share/applications"
#     "/var/lib/snapd/desktop/applications"
# )

# Safe-mode prompting during workspace open
# SAFE_MODE_PROMPTING="enabled"

# Safe-mode strictness level
# "relaxed" — only prompt if app class is missing
# "strict"  — prompt if app class, launch mode, or splash window is missing
# SAFE_MODE_STRICTNESS="relaxed"

# File logging (writes full verbose output to log file regardless of CLI flag)
# LOG_TO_FILE="disabled"

# Log directory (only used when LOG_TO_FILE is enabled)
# LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/kdoitall/logs"

# Timeout (seconds) per window during assisted close before auto-skipping
# CLOSE_WAIT_TIMEOUT=60

# Extra window positions (uncomment the array and desired positions to enable)
# EXTRA_POSITIONS=(
#     "Left Two-Thirds"
#     "Right Two-Thirds"
#     "Left 60"
#     "Right 40"
#     "Left 40"
#     "Right 60"
#     "Center Half"
#     "Left 25"
#     "Right 25"
#     "Center Two-Thirds"
#     "Top Two-Thirds"
#     "Bottom Two-Thirds"
#     "Top 60"
#     "Bottom 40"
#     "Top 40"
#     "Bottom 60"
# )
CONFIGEOF
    echo "✓ Created user config:      $USER_CONFIG"
else
    update_user_config "$USER_CONFIG"
fi

# --- Create exec wrapper ---
cat > "$BIN_DIR/kdoitall" << EOF
#!/bin/bash
exec "$PROJECT_ROOT/bin/kdoitall" "\$@"
EOF
chmod +x "$BIN_DIR/kdoitall"
echo "✓ Installed kdoitall to $BIN_DIR/kdoitall"

# --- Check PATH ---
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "⚠ $BIN_DIR is not on your PATH"
    echo "  Add this to your shell profile (~/.bashrc or ~/.bash_profile):"
    echo ""
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

# --- Summary ---
echo ""
echo "✓ Created data directory:   $DATA_DIR/"
echo "✓ Created config directory: $CONFIG_DIR/"
echo ""
echo "Next steps:"
echo "  1. Run 'kdoitall app scan' to discover installed applications"
echo "  2. Run 'kdoitall workspace create <name>' to create your first workspace"