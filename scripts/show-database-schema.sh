#!/bin/bash

# Use the same database path as kdoitall
export KDOITALL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall/kdoitall.db"

# Check if database exists
if [[ ! -f "$KDOITALL_DB" ]]; then
    echo "Error: Database not found at $KDOITALL_DB" >&2
    exit 1
fi

echo "Database Schema: $KDOITALL_DB"
echo "========================================"
echo ""

# Get list of all tables
tables=$(sqlite3 "$KDOITALL_DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" 2>/dev/null)

if [[ -z "$tables" ]]; then
    echo "No tables found in database"
    exit 0
fi

# Loop through each table and display its columns
while IFS= read -r table; do
    echo "Table: $table"
    echo "----------------------------------------"
    echo "Columns:"
    sqlite3 -column -header "$KDOITALL_DB" "PRAGMA table_info($table)"
    echo ""
    echo ""
done <<< "$tables"

echo "========================================"
echo "Total tables: $(echo "$tables" | wc -l)"