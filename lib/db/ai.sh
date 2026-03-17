#!/bin/bash

# Part of kdoitall - KDE Desktop Automation Tool
# Copyright (C) 2025 Ethan Plunk
# SPDX-License-Identifier: GPL-3.0-or-later

check_and_set_guard "_KDOITALL_DB_AI_LOADED" || return 0

ensure_ai_tables() {
    db_query "
        CREATE TABLE IF NOT EXISTS ai_task_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_name TEXT NOT NULL,
            window_name TEXT NOT NULL,
            link_reason TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(task_name, window_name)
        );"

    db_query "
        CREATE TABLE IF NOT EXISTS ai_window_importance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            task_name TEXT,
            window_name TEXT NOT NULL,
            workspace_name TEXT,
            class TEXT,
            window_title TEXT,
            importance_score INTEGER NOT NULL,
            suggested_action TEXT,
            reason TEXT,
            screenshot_path TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );"

    db_query "
        CREATE TABLE IF NOT EXISTS ai_automation_cycles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cycle_name TEXT NOT NULL,
            cycle_step INTEGER NOT NULL,
            status TEXT NOT NULL,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );"

    db_query "
        CREATE TABLE IF NOT EXISTS ai_window_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            task_name TEXT,
            parent_window_name TEXT NOT NULL,
            child_window_name TEXT NOT NULL,
            link_type TEXT NOT NULL DEFAULT 'popup',
            confidence INTEGER NOT NULL DEFAULT 0,
            rationale TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(run_id, parent_window_name, child_window_name, link_type)
        );"

    db_query "
        CREATE TABLE IF NOT EXISTS ai_run_summaries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL UNIQUE,
            task_name TEXT,
            model_name TEXT,
            task_summary TEXT,
            sqlite_state_summary TEXT,
            popup_link_summary TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );"

    db_query "CREATE INDEX IF NOT EXISTS idx_ai_window_importance_run_id ON ai_window_importance(run_id);"
    db_query "CREATE INDEX IF NOT EXISTS idx_ai_window_links_run_id ON ai_window_links(run_id);"
    db_query "CREATE INDEX IF NOT EXISTS idx_ai_window_links_task_name ON ai_window_links(task_name);"
}

db_ai_get_windows_snapshot() {
    db_query \
        "SELECT window_name, workspace_name, class, COALESCE(window_title, ''), COALESCE(uuid, '')
         FROM app_windows
         ORDER BY workspace_name, window_name;"

    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
}

db_ai_get_popup_candidates() {
    db_query \
        "SELECT window_name, workspace_name, class, COALESCE(window_title, ''), COALESCE(uuid, '')
         FROM app_windows
         WHERE LOWER(COALESCE(window_title, '')) GLOB '*dialog*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*settings*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*preferences*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*login*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*auth*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*confirm*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*warning*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*open file*'
            OR LOWER(COALESCE(window_title, '')) GLOB '*save*'
         ORDER BY workspace_name, window_name;"

    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
}

db_ai_link_task_window() {
    local task_name="$1"
    local window_name="$2"
    local link_reason="${3:-manual link}"

    db_query \
        "INSERT OR REPLACE INTO ai_task_links (task_name, window_name, link_reason)
         VALUES (:task_name, :window_name, :link_reason);" \
        ":task_name" "$task_name" \
        ":window_name" "$window_name" \
        ":link_reason" "$link_reason"
}

db_ai_record_window_score() {
    local run_id="$1"
    local task_name="$2"
    local window_name="$3"
    local workspace_name="$4"
    local class_name="$5"
    local window_title="$6"
    local importance_score="$7"
    local suggested_action="$8"
    local reason="$9"
    local screenshot_path="${10:-}"

    db_query \
        "INSERT INTO ai_window_importance (
            run_id, task_name, window_name, workspace_name, class, window_title,
            importance_score, suggested_action, reason, screenshot_path
         ) VALUES (
            :run_id, :task_name, :window_name, :workspace_name, :class, :window_title,
            :importance_score, :suggested_action, :reason, :screenshot_path
         );" \
        ":run_id" "$run_id" \
        ":task_name" "$task_name" \
        ":window_name" "$window_name" \
        ":workspace_name" "$workspace_name" \
        ":class" "$class_name" \
        ":window_title" "$window_title" \
        ":importance_score" "$importance_score" \
        ":suggested_action" "$suggested_action" \
        ":reason" "$reason" \
        ":screenshot_path" "$screenshot_path"
}

db_ai_record_window_link() {
    local run_id="$1"
    local task_name="$2"
    local parent_window_name="$3"
    local child_window_name="$4"
    local link_type="$5"
    local confidence="$6"
    local rationale="$7"

    db_query \
        "INSERT OR REPLACE INTO ai_window_links (
            run_id, task_name, parent_window_name, child_window_name,
            link_type, confidence, rationale
         ) VALUES (
            :run_id, :task_name, :parent_window_name, :child_window_name,
            :link_type, :confidence, :rationale
         );" \
        ":run_id" "$run_id" \
        ":task_name" "$task_name" \
        ":parent_window_name" "$parent_window_name" \
        ":child_window_name" "$child_window_name" \
        ":link_type" "$link_type" \
        ":confidence" "$confidence" \
        ":rationale" "$rationale"
}

db_ai_record_run_summary() {
    local run_id="$1"
    local task_name="$2"
    local model_name="$3"
    local task_summary="$4"
    local sqlite_state_summary="$5"
    local popup_link_summary="$6"

    db_query \
        "INSERT OR REPLACE INTO ai_run_summaries (
            run_id, task_name, model_name, task_summary, sqlite_state_summary, popup_link_summary
         ) VALUES (
            :run_id, :task_name, :model_name, :task_summary, :sqlite_state_summary, :popup_link_summary
         );" \
        ":run_id" "$run_id" \
        ":task_name" "$task_name" \
        ":model_name" "$model_name" \
        ":task_summary" "$task_summary" \
        ":sqlite_state_summary" "$sqlite_state_summary" \
        ":popup_link_summary" "$popup_link_summary"
}

db_ai_get_latest_window_scores() {
    local task_name="${1:-}"

    if [[ -n "$task_name" ]]; then
        db_query \
            "SELECT window_name, workspace_name, class, window_title, importance_score, COALESCE(suggested_action, ''), COALESCE(reason, '')
             FROM ai_window_importance
             WHERE run_id = (
                SELECT run_id FROM ai_window_importance
                WHERE task_name = :task_name
                ORDER BY id DESC
                LIMIT 1
             )
             ORDER BY importance_score ASC, window_name;" \
            ":task_name" "$task_name"
    else
        db_query \
            "SELECT window_name, workspace_name, class, window_title, importance_score, COALESCE(suggested_action, ''), COALESCE(reason, '')
             FROM ai_window_importance
             WHERE run_id = (
                SELECT run_id FROM ai_window_importance
                ORDER BY id DESC
                LIMIT 1
             )
             ORDER BY importance_score ASC, window_name;"
    fi

    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
}

db_ai_get_latest_window_links() {
    local task_name="${1:-}"

    if [[ -n "$task_name" ]]; then
        db_query \
            "SELECT parent_window_name, child_window_name, link_type, confidence, COALESCE(rationale, '')
             FROM ai_window_links
             WHERE run_id = (
                SELECT run_id FROM ai_window_links
                WHERE task_name = :task_name
                ORDER BY id DESC
                LIMIT 1
             )
             ORDER BY confidence DESC, parent_window_name, child_window_name;" \
            ":task_name" "$task_name"
    else
        db_query \
            "SELECT parent_window_name, child_window_name, link_type, confidence, COALESCE(rationale, '')
             FROM ai_window_links
             WHERE run_id = (
                SELECT run_id FROM ai_window_links
                ORDER BY id DESC
                LIMIT 1
             )
             ORDER BY confidence DESC, parent_window_name, child_window_name;"
    fi

    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
}

db_ai_get_latest_run_summary() {
    local task_name="${1:-}"

    if [[ -n "$task_name" ]]; then
        db_query \
            "SELECT run_id, COALESCE(task_name, ''), COALESCE(model_name, ''),
                    COALESCE(task_summary, ''), COALESCE(sqlite_state_summary, ''),
                    COALESCE(popup_link_summary, ''), created_at
             FROM ai_run_summaries
             WHERE task_name = :task_name
             ORDER BY id DESC
             LIMIT 1;" \
            ":task_name" "$task_name"
    else
        db_query \
            "SELECT run_id, COALESCE(task_name, ''), COALESCE(model_name, ''),
                    COALESCE(task_summary, ''), COALESCE(sqlite_state_summary, ''),
                    COALESCE(popup_link_summary, ''), created_at
             FROM ai_run_summaries
             ORDER BY id DESC
             LIMIT 1;"
    fi

    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
}

db_ai_start_cycle() {
    local cycle_name="$1"
    local notes="${2:-cycle started}"

    db_query \
        "INSERT INTO ai_automation_cycles (cycle_name, cycle_step, status, notes)
         VALUES (:cycle_name, 1, 'active', :notes);" \
        ":cycle_name" "$cycle_name" \
        ":notes" "$notes"
}

db_ai_step_cycle() {
    local cycle_name="$1"
    local status="$2"
    local notes="$3"

    db_query \
        "INSERT INTO ai_automation_cycles (cycle_name, cycle_step, status, notes)
         VALUES (
            :cycle_name,
            COALESCE((SELECT MAX(cycle_step) + 1 FROM ai_automation_cycles WHERE cycle_name = :cycle_name), 1),
            :status,
            :notes
         );" \
        ":cycle_name" "$cycle_name" \
        ":status" "$status" \
        ":notes" "$notes"
}

db_ai_cycle_status() {
    local cycle_name="${1:-}"

    if [[ -n "$cycle_name" ]]; then
        db_query \
            "SELECT cycle_name, cycle_step, status, COALESCE(notes, ''), created_at
             FROM ai_automation_cycles
             WHERE cycle_name = :cycle_name
             ORDER BY id DESC
             LIMIT 10;" \
            ":cycle_name" "$cycle_name"
    else
        db_query \
            "SELECT cycle_name, cycle_step, status, COALESCE(notes, ''), created_at
             FROM ai_automation_cycles
             ORDER BY id DESC
             LIMIT 10;"
    fi

    [[ ${#DB_RESULT[@]} -gt 0 ]] && printf '%s\n' "${DB_RESULT[@]}"
}
