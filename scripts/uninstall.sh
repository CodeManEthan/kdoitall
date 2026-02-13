#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

echo "Uninstalling kdoitall..."
echo ""

# --- Remove exec wrapper ---
BIN_FILE="$HOME/.local/bin/kdoitall"
if [[ -f "$BIN_FILE" ]]; then
    rm -f "$BIN_FILE"
    echo "✓ Removed $BIN_FILE"
else
    echo "  $BIN_FILE not found, skipping"
fi

# --- Ask about data removal ---
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kdoitall"
if [[ -d "$DATA_DIR" ]]; then
    echo ""
    echo "Remove kdoitall data? This includes your database and workspace scripts."
    echo "  Location: $DATA_DIR/"
    read -rp "  [y/N]: " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        rm -rf "$DATA_DIR"
        echo "✓ Removed $DATA_DIR/"
    else
        echo "  Kept $DATA_DIR/"
    fi
fi

# --- Ask about config removal ---
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kdoitall"
if [[ -d "$CONFIG_DIR" ]]; then
    echo ""
    echo "Remove kdoitall configuration?"
    echo "  Location: $CONFIG_DIR/"
    read -rp "  [y/N]: " remove_config
    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo "✓ Removed $CONFIG_DIR/"
    else
        echo "  Kept $CONFIG_DIR/"
    fi
fi

# --- Summary ---
echo ""
echo "kdoitall has been uninstalled."
echo "The cloned repository has not been removed — delete it manually if desired."