#!/bin/bash

# Use the same database path as kdoitall
export KDOITALL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"

# Check if database exists
if [[ ! -f "$KDOITALL_DB" ]]; then
    echo "Error: Database not found at $KDOITALL_DB" >&2
    exit 1
fi

echo "Database: $KDOITALL_DB"
echo "========================================"
echo ""

# Check if workspace_definitions table exists
if ! sqlite3 "$KDOITALL_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='workspace_definitions'" | grep -q workspace_definitions; then
    echo "Error: workspace_definitions table not found" >&2
    exit 1
fi

# Get row count
count=$(sqlite3 "$KDOITALL_DB" "SELECT COUNT(*) FROM workspace_definitions" 2>/dev/null || echo "0")

echo "Table: workspace_definitions ($count rows)"
echo "----------------------------------------"

if [ "$count" -eq 0 ]; then
    echo "  (empty)"
else
    # Pretty-printed output with column mode
    sqlite3 -column -header "$KDOITALL_DB" "SELECT * FROM workspace_definitions"
fi

echo ""
echo "========================================"