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

# Get list of all tables
tables=$(sqlite3 "$KDOITALL_DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" 2>/dev/null)

if [[ -z "$tables" ]]; then
    echo "No tables found in database"
    exit 0
fi

# Loop through each table and display its contents
while IFS= read -r table; do
    # Get row count
    count=$(sqlite3 "$KDOITALL_DB" "SELECT COUNT(*) FROM $table" 2>/dev/null || echo "0")
    
    echo "Table: $table ($count rows)"
    echo "----------------------------------------"
    
    if [ "$count" -eq 0 ]; then
        echo "  (empty)"
    else
        # Pretty-printed output with column mode
        sqlite3 -column -header "$KDOITALL_DB" "SELECT * FROM $table"
    fi
    
    echo ""
done <<< "$tables"

echo "========================================"
echo "Total tables: $(echo "$tables" | wc -l)"