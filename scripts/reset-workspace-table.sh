#!/bin/bash
# Reset only workspace_definitions table - useful during development

set -euo pipefail

# Database path
DB_DIR="$HOME/.local/share/kdoitall"
DB_FILE="$DB_DIR/kdoitall.db"

# Verify database exists
if [[ ! -f "$DB_FILE" ]]; then
    echo "✗ Error: Database not found at $DB_FILE"
    echo "  Run reset-db.sh to create the database first"
    exit 1
fi

# Reset workspace_definitions table
sqlite3 "$DB_FILE" <<SQL
-- Drop the table (CASCADE will handle any foreign key constraints)
DROP TABLE IF EXISTS workspace_definitions;

-- Recreate the table
CREATE TABLE workspace_definitions (
    workspace_name TEXT PRIMARY KEY,
    description TEXT,
    is_active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_opened_at TIMESTAMP
);
SQL

echo "✓ workspace_definitions table reset complete"
echo "  Database: $DB_FILE"