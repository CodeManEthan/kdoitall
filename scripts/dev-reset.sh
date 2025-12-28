#!/bin/bash
# Reset everything - useful during development

set -euo pipefail

# Remove database
rm -f "$HOME/.local/share/kdoitall/kdoitall.db"

# Recreate
sqlite3 "$HOME/.local/share/kdoitall/kdoitall.db" < database/schema.sql

echo "✓ Database reset complete"