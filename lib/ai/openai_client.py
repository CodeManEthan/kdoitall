#!/usr/bin/env python3
"""OpenAI Responses API client for advanced kdoitall AI workflows."""

import json
import os
import re
import sys
import urllib.request

API_URL = "https://api.openai.com/v1/responses"


def _parse_json_text(text: str):
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?", "", text).strip()
        text = re.sub(r"```$", "", text).strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"error": "Model output was not valid JSON", "raw": text}


def _post(payload):
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        return {"error": "OPENAI_API_KEY is not set"}

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except Exception as exc:  # noqa: BLE001
        return {"error": f"OpenAI API request failed: {exc}"}

    text = parsed.get("output_text", "").strip()
    if not text:
        return {"error": "OpenAI API returned no output_text"}

    return _parse_json_text(text)


def _base_payload(model: str, system_prompt: str, user_payload: dict):
    return {
        "model": model,
        "input": [
            {
                "role": "system",
                "content": [{"type": "input_text", "text": system_prompt}],
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": json.dumps(user_payload, ensure_ascii=False),
                    }
                ],
            },
        ],
        "text": {"format": {"type": "json_object"}},
    }


def rank_windows(task_name, windows_json):
    model = os.environ.get("OPENAI_MODEL", "gpt-5")
    windows = json.loads(windows_json)
    prompt = (
        "You are an expert KDE desktop orchestrator. "
        "Use window names, classes, titles, and screenshot paths as signals. "
        "Return strict JSON with keys: "
        "task_summary (string), sqlite_state_summary (string), "
        "automation_cycle (array of short steps), "
        "window_scores (array). Each window_scores item must include "
        "window_name (string), importance (0-100 integer), "
        "suggested_action (keep|close|minimize|focus), reason (short string)."
    )
    payload = _base_payload(model, prompt, {"task": task_name, "windows": windows})
    return _post(payload)


def link_popups(task_name, windows_json, popup_candidates_json):
    model = os.environ.get("OPENAI_MODEL", "gpt-5")
    windows = json.loads(windows_json)
    popup_candidates = json.loads(popup_candidates_json)

    prompt = (
        "You are an expert in parent/child desktop window topology. "
        "Match popup/dialog windows to the best parent app window using class, title, workspace, and screenshot context. "
        "Return strict JSON with keys: popup_link_summary (string), sqlite_change_summary (string), popup_links (array). "
        "Each popup_links item must include: parent_window_name (string), child_window_name (string), "
        "link_type (popup|dialog|auth|filepicker|notification), confidence (0-100 integer), rationale (short string)."
    )
    payload = _base_payload(
        model,
        prompt,
        {"task": task_name, "windows": windows, "popup_candidates": popup_candidates},
    )
    return _post(payload)


def generate_ideas(context):
    model = os.environ.get("OPENAI_MODEL", "gpt-5")
    prompt = (
        "Generate exactly 15 concise, practical feature ideas for KDE desktop automation. "
        "Return strict JSON object with key ideas, where ideas is an array of 15 strings."
    )
    payload = _base_payload(model, prompt, {"context": context})
    return _post(payload)


def main():
    if len(sys.argv) < 2:
        print(
            json.dumps(
                {
                    "error": "usage: openai_client.py <rank|popup-link|ideas> [args]",
                }
            )
        )
        return 1

    mode = sys.argv[1]
    if mode == "rank":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "usage: rank <task_name> <windows_json>"}))
            return 1
        result = rank_windows(sys.argv[2], sys.argv[3])
    elif mode == "popup-link":
        if len(sys.argv) < 5:
            print(
                json.dumps(
                    {
                        "error": "usage: popup-link <task_name> <windows_json> <popup_candidates_json>",
                    }
                )
            )
            return 1
        result = link_popups(sys.argv[2], sys.argv[3], sys.argv[4])
    elif mode == "ideas":
        context = sys.argv[2] if len(sys.argv) >= 3 else ""
        result = generate_ideas(context)
    else:
        result = {"error": f"unknown mode: {mode}"}

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
