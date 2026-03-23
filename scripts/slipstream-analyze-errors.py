#!/usr/bin/env python3
from __future__ import annotations
"""
slipstream-analyze-errors.py
Reads the errors JSONL for the current project, groups repeated tool
failures by pattern, and flags systemic issues. Outputs JSON to stdout.

Usage: python3 slipstream-analyze-errors.py [--cwd PATH]
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


def normalize_command(cmd: str) -> str:
    """Keep executable + first subcommand; strip arguments."""
    cmd = cmd.strip()
    # Split on spaces, keep first 2-3 tokens (executable + subcommand)
    tokens = cmd.split()
    if len(tokens) <= 2:
        return cmd
    # Keep "npm run e2e" style (3 tokens) if second token is "run"/"test"/"exec"
    if len(tokens) >= 3 and tokens[1] in ("run", "test", "exec", "manage.py", "build"):
        return " ".join(tokens[:3])
    return " ".join(tokens[:2])


def project_key_for(cwd: str) -> str:
    return cwd.replace("/", "-")


def load_cursor(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def load_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    records = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", default=os.getcwd())
    args = parser.parse_args()

    cwd = args.cwd
    project_key = project_key_for(cwd)
    home = Path.home()
    data_dir = home / ".slipstream"
    project_dir = data_dir / "projects" / project_key
    cursor_path = data_dir / "cursors" / f"{project_key}.json"

    cursor = load_cursor(cursor_path)
    last_review = cursor.get("last_errors_review", "")

    records = load_jsonl(project_dir / "errors.jsonl")
    total = len(records)
    new_count = sum(1 for r in records if r.get("timestamp", "") > last_review) if last_review else total

    distinct_tools = sorted({r.get("tool_name", "") for r in records if r.get("tool_name")})

    by_pattern: dict[str, dict] = defaultdict(lambda: {
        "sessions": set(), "count": 0, "last_seen": "", "raw_commands": []
    })

    for r in records:
        tool_name = r.get("tool_name", "")
        tool_input = r.get("tool_input", {})
        session_id = r.get("session_id", "")
        ts = r.get("timestamp", "")

        if tool_name == "Bash":
            cmd = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
            norm = normalize_command(cmd)
        else:
            cmd = ""
            norm = tool_name

        key = f"{tool_name}:{norm}"
        by_pattern[key]["tool_name"] = tool_name
        by_pattern[key]["normalized_command"] = norm
        by_pattern[key]["sessions"].add(session_id)
        by_pattern[key]["count"] += 1
        by_pattern[key]["last_seen"] = max(by_pattern[key]["last_seen"], ts)
        if cmd:
            by_pattern[key]["raw_commands"].append(cmd[:100])

    patterns = []
    for key, info in by_pattern.items():
        session_list = sorted(info["sessions"])
        if len(session_list) < 2:
            continue
        patterns.append({
            "tool_name": info["tool_name"],
            "normalized_command": info["normalized_command"],
            "count": info["count"],
            "session_count": len(session_list),
            "sessions": session_list,
            "last_seen": info["last_seen"],
            "raw_commands": list(dict.fromkeys(info["raw_commands"]))[:5],
            "systemic": info["count"] >= 4,
        })

    patterns.sort(key=lambda p: p["count"], reverse=True)

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total": total,
        "new_since_review": new_count,
        "last_review": last_review,
        "distinct_tools": distinct_tools,
        "patterns": patterns,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "total": 0, "patterns": []}))
    sys.exit(0)
