#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_SNAPSHOT_LOADED" || return 0

# Atomic window-state snapshot via a custom KWin script.
#
# kdotool emits each search result as a separate asynchronous DBus signal,
# producing the prefix-truncation race documented in
# docs/flows/window-detection.md edge case #9. This module replaces the
# query path with one synchronous invocation of a KWin script we ship under
# lib/kwin-scripts/. The script walks workspace.windowList() and delivers
# the entire result as one batched DBus method call to a receiver we
# register before we trigger the script — both ends ours, no race window.
#
# snapshot_all_windows() is the public entry point. It populates the same
# global arrays that the kdotool-based refresh_current_windows() does
# (CURRENT_UUIDS, CURRENT_CLASSES, CURRENT_TITLES) so callers don't change.
# Returns non-zero when the snapshot tool or its deps are unavailable, so
# callers can fall back to the kdotool path.

_SNAPSHOT_TOOL="${LIB_DIR}/kwin-scripts/snapshot.sh"
_SNAPSHOT_AVAILABILITY=""  # cached: "" unchecked, "yes" available, "no" unavailable

snapshot_available() {
    local function_name="snapshot_available"

    if [[ -n "$_SNAPSHOT_AVAILABILITY" ]]; then
        [[ "$_SNAPSHOT_AVAILABILITY" == "yes" ]]
        return $?
    fi

    if [[ ! -x "$_SNAPSHOT_TOOL" ]]; then
        debug_log "$function_name" "snapshot tool not executable: $_SNAPSHOT_TOOL"
        _SNAPSHOT_AVAILABILITY="no"
        return 1
    fi

    if ! command -v python3 &>/dev/null; then
        debug_log "$function_name" "python3 missing"
        _SNAPSHOT_AVAILABILITY="no"
        return 1
    fi

    if ! python3 -c "import dbus, dbus.service, dbus.mainloop.glib; from gi.repository import GLib" &>/dev/null; then
        debug_log "$function_name" "python3 dbus/gobject deps missing"
        _SNAPSHOT_AVAILABILITY="no"
        return 1
    fi

    if ! command -v qdbus-qt6 &>/dev/null && ! command -v qdbus6 &>/dev/null; then
        debug_log "$function_name" "qdbus-qt6 / qdbus6 missing"
        _SNAPSHOT_AVAILABILITY="no"
        return 1
    fi

    _SNAPSHOT_AVAILABILITY="yes"
    return 0
}

snapshot_all_windows() {
    local function_name="snapshot_all_windows"
    debug_function_enter "$function_name"

    if ! snapshot_available; then
        debug_log "$function_name" "snapshot path unavailable"
        debug_function_exit "$function_name"
        return 1
    fi

    local payload=""
    payload=$("$_SNAPSHOT_TOOL" 2>/dev/null) || {
        debug_log "$function_name" "snapshot tool exited non-zero"
        debug_function_exit "$function_name"
        return 1
    }

    if [[ -z "$payload" ]]; then
        debug_log "$function_name" "snapshot returned empty payload"
        debug_function_exit "$function_name"
        return 1
    fi

    local count=""
    count=$(jq -r '.windowCount // empty' <<< "$payload" 2>/dev/null) || {
        debug_log "$function_name" "snapshot payload not valid JSON"
        debug_function_exit "$function_name"
        return 1
    }

    if [[ -z "$count" ]]; then
        debug_log "$function_name" "snapshot payload missing windowCount"
        debug_function_exit "$function_name"
        return 1
    fi

    CURRENT_UUIDS=()
    CURRENT_CLASSES=()
    CURRENT_TITLES=()

    # Emit each window as three lines (uuid, class, title) to keep parsing
    # tolerant of any character that might appear in titles (tabs, newlines
    # in a caption are unusual but not impossible). jq -r prints raw strings.
    local uuid="" class="" title=""
    while IFS= read -r uuid && IFS= read -r class && IFS= read -r title; do
        [[ -z "$uuid" ]] && continue
        CURRENT_UUIDS+=("$uuid")
        CURRENT_CLASSES+=("${class:-N/A}")
        CURRENT_TITLES+=("${title:-N/A}")
    done < <(jq -r '.windows[] | (.internalId, .resourceClass, .caption)' <<< "$payload" 2>/dev/null)

    debug_log "$function_name" "Retrieved ${#CURRENT_UUIDS[@]} windows via KWin snapshot"
    debug_function_exit "$function_name"
    return 0
}
