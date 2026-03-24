#!/usr/bin/env python3
from __future__ import annotations
"""
slipstream-analyze-corrections.py
Reads unanalyzed session transcripts for the current project and finds
correction turns (user correcting Claude). Outputs JSON to stdout.

Usage: python3 slipstream-analyze-corrections.py [--cwd PATH]
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

CORRECTION_PATTERNS = re.compile(
    r"\bno\b|don'?t\b|\bstop\b|\bwait\b|\bactually\b"
    r"|that'?s not|that'?s wrong"
    r"|\binstead\b|\brather\b"
    r"|what i meant|i said|i meant"
    r"|\brevert\b|\bundo\b|go back"
    r"|remove what you just|don'?t do that|not what i"
    r"|\bwrong\b|please don|you should not|should not have"
    r"|i asked you|i told you|\bnever\b|\bincorrect\b",
    re.IGNORECASE,
)

NATIVE_TOOL_MAP = {
    re.compile(r"\bgrep\b"): "Grep",
    re.compile(r"\brg\b|\bripgrep\b"): "Grep",
    re.compile(r"\bfind\b"): "Glob",
    re.compile(r"\bls\b"): "Glob",
    re.compile(r"\bcat\b|\bhead\b|\btail\b"): "Read",
    re.compile(r"\bsed\s+-i\b"): "Edit",
}


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


def find_corrections(messages: list[dict], session_id: str) -> list[dict]:
    corrections = []
    if len(messages) < 4:
        return corrections

    for i, msg in enumerate(messages):
        if msg.get("type") != "user":
            continue

        # Find preceding assistant turn
        prev_assistant = None
        for j in range(i - 1, -1, -1):
            if messages[j].get("type") == "assistant":
                prev_assistant = messages[j]
                break

        if prev_assistant is None:
            continue

        content = extract_text(msg.get("message", {}).get("content", ""))
        if is_automated(content):
            continue

        match = CORRECTION_PATTERNS.search(content)
        if not match:
            continue

        asst_content = extract_text(
            prev_assistant.get("message", {}).get("content", "")
        )

        corrections.append({
            "session_id": session_id,
            "assistant_text": asst_content[:300],
            "correction_text": content[:300],
            "keywords": [match.group(0)],
        })

    return corrections



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
    state_path = data_dir / "corrections-state.json"

    analyzed = load_state(state_path)

    all_sessions = {p.stem for p in sessions_dir.glob("*.jsonl")} if sessions_dir.is_dir() else set()
    unanalyzed_ids = sorted(all_sessions - analyzed)

    corrections = []
    for sid in unanalyzed_ids:
        session_path = sessions_dir / f"{sid}.jsonl"
        messages = parse_session(session_path)
        corrections.extend(find_corrections(messages, sid))

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total_sessions": len(all_sessions),
        "already_analyzed": len(analyzed & all_sessions),
        "unanalyzed_count": len(unanalyzed_ids),
        "unanalyzed_session_ids": unanalyzed_ids,
        "corrections": corrections,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "corrections": [], "unanalyzed_count": 0}))
    sys.exit(0)
