#!/bin/bash

# Use the same database path as kdoitall
export KDOITALL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"

# Check if database exists
if [[ ! -f "$KDOITALL_DB" ]]; then
    echo "Error: Database not found at $KDOITALL_DB" >&2
    exit 1
fi

# Get row count
count=$(sqlite3 "$KDOITALL_DB" "SELECT COUNT(*) FROM app_windows" 2>/dev/null || echo "0")

echo "app_windows table ($count rows):"
echo "Database: $KDOITALL_DB"
echo ""

if [ "$count" -eq 0 ]; then
    echo "  (empty)"
else
    # Pretty-printed output with column mode
    sqlite3 -column -header "$KDOITALL_DB" "SELECT * FROM app_windows ORDER BY workspace_name, window_name"
fi

echo ""