#!/usr/bin/env python3
"""
slipstream-analyze-memory.py
Reads unanalyzed session transcripts for the current project and finds
user-level signals (role, preferences, knowledge, corrections about self).
Outputs JSON to stdout.

Usage: python3 slipstream-analyze-memory.py [--cwd PATH]
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

# Patterns that signal user-level facts
SIGNAL_PATTERNS = [
    (re.compile(r"\bI'?m\s+(?:a|an|the)\s+\w", re.IGNORECASE), "role"),
    (re.compile(r"\bI\s+am\s+(?:a|an|the)\s+\w", re.IGNORECASE), "role"),
    (re.compile(r"\bI'?ve\s+been\s+\w+ing\b", re.IGNORECASE), "role"),
    (re.compile(r"\bas\s+(?:a|an|the)\s+\w+\s+(?:who|with|focused)", re.IGNORECASE), "role"),
    (re.compile(r"\bkeep\s+(?:your\s+)?responses\s+\w+", re.IGNORECASE), "feedback"),
    (re.compile(r"\bdon'?t\s+(?:add|include|use)\s+\w+", re.IGNORECASE), "feedback"),
    (re.compile(r"\balways\s+(?:show|use|include|start)\b", re.IGNORECASE), "feedback"),
    (re.compile(r"\bI\s+prefer\b", re.IGNORECASE), "feedback"),
    (re.compile(r"\bI\s+(?:like|hate|dislike)\s+when\b", re.IGNORECASE), "feedback"),
    (re.compile(r"\bI\s+know\s+\w+\s+but\b", re.IGNORECASE), "user"),
    (re.compile(r"\bthis\s+is\s+my\s+first\s+\w+\s+project\b", re.IGNORECASE), "user"),
    (re.compile(r"\bI'?ve\s+(?:been\s+writing|been\s+using|used)\s+\w+\s+for\s+\d+\s+years?\b", re.IGNORECASE), "user"),
    (re.compile(r"\bI\s+run\s+a\b", re.IGNORECASE), "role"),
    (re.compile(r"\bmy\s+(?:company|startup|team|fund|firm)\b", re.IGNORECASE), "role"),
]


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


def parse_session(path: Path) -> list[dict]:
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
        pass
    return messages


def find_signals(messages: list[dict], session_id: str) -> list[dict]:
    signals = []
    for msg in messages:
        if msg.get("type") != "user":
            continue
        content = extract_text(msg.get("message", {}).get("content", ""))
        if is_automated(content):
            continue
        for pattern, signal_type in SIGNAL_PATTERNS:
            m = pattern.search(content)
            if m:
                # Get surrounding context (up to 200 chars around the match)
                start = max(0, m.start() - 50)
                end = min(len(content), m.end() + 150)
                signals.append({
                    "session_id": session_id,
                    "signal_type": signal_type,
                    "matched": m.group(0),
                    "context": content[start:end].strip(),
                })
                break  # one signal per message turn
    return signals


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", default=os.getcwd())
    args = parser.parse_args()

    cwd = args.cwd
    project_key = project_key_for(cwd)
    home = Path.home()
    data_dir = home / ".slipstream"
    sessions_dir = home / ".claude" / "projects" / project_key
    state_path = data_dir / "memory-state.json"

    analyzed = load_state(state_path)
    all_sessions = {p.stem for p in sessions_dir.glob("*.jsonl")} if sessions_dir.is_dir() else set()
    unanalyzed_ids = sorted(all_sessions - analyzed)

    signals = []
    for sid in unanalyzed_ids:
        session_path = sessions_dir / f"{sid}.jsonl"
        messages = parse_session(session_path)
        signals.extend(find_signals(messages, sid))

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total_sessions": len(all_sessions),
        "already_analyzed": len(analyzed & all_sessions),
        "unanalyzed_count": len(unanalyzed_ids),
        "unanalyzed_session_ids": unanalyzed_ids,
        "signals": signals,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "signals": [], "unanalyzed_count": 0}))
    sys.exit(0)
