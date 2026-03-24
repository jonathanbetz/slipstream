#!/usr/bin/env python3
from __future__ import annotations
"""
slipstream-analyze-commands.py
Reads unanalyzed session transcripts for the current project and extracts
the opening task and major pivots from each session. Outputs JSON to stdout.
Claude then groups these semantically to identify repeated workflows.

Usage: python3 slipstream-analyze-commands.py [--cwd PATH]
"""

import argparse
import json
import os
import sys
from pathlib import Path


def project_key_for(cwd: str) -> str:
    return cwd.replace("/", "-")


def load_state(path: Path) -> set:
    if not path.is_file():
        return set()
    try:
        return set(json.loads(path.read_text()).get("analyzed_session_ids", []))
    except Exception:
        return set()


def extract_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                parts.append(part.get("text", ""))
            elif isinstance(part, str):
                parts.append(part)
        return " ".join(parts)
    return str(content)


def is_automated(text: str) -> bool:
    return (
        "tool_use_id" in text
        or "<tool_result" in text
        or "<scheduled-task" in text
    )


def parse_session(path: Path) -> dict:
    """Extract opening task and pivots from a session transcript."""
    messages = []
    try:
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if obj.get("type") in ("user", "assistant"):
                    messages.append(obj)
            except json.JSONDecodeError:
                pass
    except Exception:
        return {}

    if len(messages) < 2:
        return {}

    # Find first real user message
    opening_task = ""
    first_user_idx = -1
    for i, msg in enumerate(messages):
        if msg.get("type") == "user":
            text = extract_text(msg.get("message", {}).get("content", ""))
            if not is_automated(text) and text.strip():
                opening_task = text[:400]
                first_user_idx = i
                break

    if not opening_task:
        return {}

    # Find pivots: substantial user messages after several turns
    pivots = []
    assistant_count = 0
    for i, msg in enumerate(messages):
        if i <= first_user_idx:
            continue
        if msg.get("type") == "assistant":
            assistant_count += 1
        if msg.get("type") == "user" and assistant_count >= 3:
            text = extract_text(msg.get("message", {}).get("content", ""))
            if not is_automated(text) and len(text) > 50:
                pivots.append(text[:300])
                assistant_count = 0  # reset after pivot

    return {
        "opening_task": opening_task,
        "pivots": pivots[:3],  # cap at 3 pivots
        "turn_count": len(messages),
    }



def parse_since(value: str) -> str:
    """Parse a duration string like '7d', '6h', '30m' into an ISO timestamp."""
    import re as _re
    from datetime import datetime, timedelta, timezone
    m = _re.fullmatch(r"(\d+)([dhm])", value.strip().lower())
    if not m:
        raise ValueError(f"Invalid --since value {value!r}. Use e.g. 7d, 6h, 30m.")
    amount, unit = int(m.group(1)), m.group(2)
    delta = {"d": timedelta(days=amount), "h": timedelta(hours=amount), "m": timedelta(minutes=amount)}[unit]
    return (datetime.now(timezone.utc) - delta).strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--since", default=None, help="Override cursor: treat events newer than this window as new (e.g. 7d, 6h, 30m)")
    args = parser.parse_args()

    cwd = args.cwd
    project_key = project_key_for(cwd)
    home = Path.home()
    data_dir = home / ".slipstream"
    sessions_dir = home / ".claude" / "projects" / project_key
    state_path = data_dir / "commands-state.json"

    analyzed = load_state(state_path)
    all_sessions = {p.stem for p in sessions_dir.glob("*.jsonl")} if sessions_dir.is_dir() else set()
    unanalyzed_ids = sorted(all_sessions - analyzed)

    sessions = []
    for sid in unanalyzed_ids:
        session_path = sessions_dir / f"{sid}.jsonl"
        info = parse_session(session_path)
        if info:
            sessions.append({"session_id": sid, **info})

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total_sessions": len(all_sessions),
        "already_analyzed": len(analyzed & all_sessions),
        "unanalyzed_count": len(unanalyzed_ids),
        "unanalyzed_session_ids": unanalyzed_ids,
        "sessions": sessions,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "sessions": [], "unanalyzed_count": 0}))
    sys.exit(0)
