#!/usr/bin/env python3
"""Persistent sqlite3 query server for bash IPC via coproc."""

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

import sqlite3
import sys


def readline():
    line = sys.stdin.readline()
    if not line:
        return None
    return line.rstrip('\n')


def respond_ok(rows=None):
    print("OK", flush=False)
    if rows:
        for row in rows:
            print(row, flush=False)
    print("---", flush=True)


def respond_err(msg):
    print("ERR", flush=False)
    print(msg.replace('\n', ' '), flush=False)
    print("---", flush=True)


def main():
    connections = {}

    while True:
        db_path = readline()
        if db_path is None or db_path == "QUIT":
            break

        query = readline()
        count_str = readline()

        if query is None or count_str is None:
            break

        try:
            param_count = int(count_str)
        except ValueError:
            while True:
                l = readline()
                if l is None or l == "---":
                    break
            respond_err(f"Invalid param count: {count_str}")
            continue

        params = {}
        for _ in range(param_count):
            key = readline()
            value = readline()
            if key is None or value is None:
                break
            params[key] = value

        end = readline()
        if end != "---":
            respond_err(f"Protocol error: expected ---, got: {end}")
            continue

        try:
            if db_path not in connections:
                connections[db_path] = sqlite3.connect(db_path)
                connections[db_path].execute("PRAGMA foreign_keys = ON;")

            conn = connections[db_path]
            cursor = conn.execute(query, params)

            rows = []
            if cursor.description:
                # SELECT — return result rows
                rows = [
                    "|".join(str(v) if v is not None else "" for v in row)
                    for row in cursor.fetchall()
                ]
            else:
                # INSERT/UPDATE/DELETE — return affected rowcount
                rows = [str(cursor.rowcount)]
            conn.commit()
            respond_ok(rows)

        except Exception as e:
            respond_err(str(e))

    for conn in connections.values():
        conn.close()


if __name__ == "__main__":
    main()
