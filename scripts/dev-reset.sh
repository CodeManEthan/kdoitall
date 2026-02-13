#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

# Reset everything - useful during development

set -euo pipefail

# Determine project root (script is in <project_root>/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Database paths
DB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall"
DB_FILE="$DB_DIR/kdoitall.db"
SCHEMA_FILE="$PROJECT_ROOT/database/schema.sql"

# Verify schema file exists
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "✗ Error: Schema file not found at $SCHEMA_FILE"
    exit 1
fi

# Remove database
if [[ -f "$DB_FILE" ]]; then
    rm -f "$DB_FILE"
    echo "✓ Removed existing database"
fi

# Ensure database directory exists
mkdir -p "$DB_DIR"

# Recreate database
sqlite3 "$DB_FILE" < "$SCHEMA_FILE"

echo "✓ Database reset complete"
echo "  Schema: $SCHEMA_FILE"
echo "  Database: $DB_FILE"