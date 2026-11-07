#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

# --- Configuration ---
KDOTOOL_VERSION="0.2.2"
KDOTOOL_REPO="jinliu/kdotool"
KDOTOOL_INSTALL_DIR="${HOME}/.local/bin"

setup_kdotool() {
    # Already installed — nothing to do
    if command -v kdotool &> /dev/null; then
        echo "✓ kdotool is already installed: $(command -v kdotool)"
        return 0
    fi

    echo "kdotool is not installed. It is required for window management."
    echo ""
    echo "How would you like to install kdotool?"
    echo ""
    echo "  1) Automatic — download and install kdotool v${KDOTOOL_VERSION}"
    echo "     installs to ${KDOTOOL_INSTALL_DIR}/"
    echo "  2) Manual    — show instructions and exit"
    echo ""

    local choice=""
    while true; do
        read -rp "Choose [1/2]: " choice
        case "$choice" in
            1) break ;;
            2)
                _kdotool_manual_instructions
                return 1
                ;;
            *)
                echo "Please enter 1 or 2."
                ;;
        esac
    done

    _kdotool_auto_install
}

_kdotool_manual_instructions() {
    echo ""
    echo "Install kdotool manually:"
    echo ""
    echo "  Option A — Download pre-built binary (x86_64 only):"
    echo "    https://github.com/${KDOTOOL_REPO}/releases"
    echo ""
    echo "  Option B — Install via cargo:"
    echo "    cargo install kdotool"
    echo "    (requires Rust: https://rustup.rs)"
    echo ""
    echo "  Option C — Arch Linux (AUR):"
    echo "    paru -S kdotool  (or yay, etc.)"
    echo ""
    echo "Once installed, re-run: bash scripts/install.sh"
}

_kdotool_auto_install() {
    # Architecture check
    local arch=""
    arch="$(uname -m)"

    if [[ "$arch" != "x86_64" ]]; then
        echo "" >&2
        echo "Error: Pre-built kdotool binaries are only available for x86_64." >&2
        echo "Your architecture: $arch" >&2
        echo ""
        _kdotool_manual_instructions
        return 1
    fi

    # Check for download tool
    local download_cmd=""
    if command -v curl &> /dev/null; then
        download_cmd="curl"
    elif command -v wget &> /dev/null; then
        download_cmd="wget"
    else
        echo "Error: curl or wget is required to download kdotool." >&2
        return 1
    fi

    # Build URL
    local tarball=""
    tarball="kdotool-${KDOTOOL_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
    local url=""
    url="https://github.com/${KDOTOOL_REPO}/releases/download/v${KDOTOOL_VERSION}/${tarball}"

    # Download to temp directory.
    # NOTE: tmp_dir must NOT be `local` — the EXIT trap below is on the shell,
    # not the function, so it fires after this function returns when install.sh
    # itself exits. A `local` would be out of scope by then, breaking cleanup
    # silently and triggering an "unbound variable" error under `set -u`.
    tmp_dir="$(mktemp -d)"
    trap '[[ -n "${tmp_dir:-}" && "${tmp_dir}" == /tmp/* ]] && rm -r "${tmp_dir}"' EXIT

    echo ""
    echo "Downloading kdotool v${KDOTOOL_VERSION}..."

    if [[ "$download_cmd" == "curl" ]]; then
        if ! curl -fSL --progress-bar -o "${tmp_dir}/${tarball}" "$url"; then
            echo "Error: Failed to download kdotool." >&2
            return 1
        fi
    else
        if ! wget --show-progress -qO "${tmp_dir}/${tarball}" "$url"; then
            echo "Error: Failed to download kdotool." >&2
            return 1
        fi
    fi

    # Extract
    echo "Extracting..."
    tar xzf "${tmp_dir}/${tarball}" -C "$tmp_dir"

    # Find the binary
    local binary_path=""
    binary_path="$(find "$tmp_dir" -name "kdotool" -type f -executable 2>/dev/null | head -n 1)"

    if [[ -z "$binary_path" ]]; then
        # May not have executable bit set in tarball
        binary_path="$(find "$tmp_dir" -name "kdotool" -type f ! -name "*.gz" | head -n 1)"
    fi

    if [[ -z "$binary_path" ]]; then
        echo "Error: Could not find kdotool binary in downloaded archive." >&2
        return 1
    fi

    # Install
    mkdir -p "$KDOTOOL_INSTALL_DIR"
    cp "$binary_path" "${KDOTOOL_INSTALL_DIR}/kdotool"
    chmod +x "${KDOTOOL_INSTALL_DIR}/kdotool"

    # Verify
    if "${KDOTOOL_INSTALL_DIR}/kdotool" --version &> /dev/null; then
        echo "✓ Installed kdotool v${KDOTOOL_VERSION} to ${KDOTOOL_INSTALL_DIR}/kdotool"
    else
        echo "⚠ kdotool was installed but could not be verified." >&2
        echo "  You may need to check: ${KDOTOOL_INSTALL_DIR}/kdotool" >&2
    fi
}

# Allow sourcing or direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_kdotool
fi
