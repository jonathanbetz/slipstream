#!/usr/bin/env python3
from __future__ import annotations
"""
slipstream-analyze-permissions.py
Reads the permissions JSONL for the current project, groups by normalized
command pattern, and identifies allow-list candidates and native-tool
substitution opportunities. Outputs JSON to stdout.

Usage: python3 slipstream-analyze-permissions.py [--cwd PATH]
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

# Bash commands that have Claude Code native equivalents
NATIVE_TOOLS = [
    (re.compile(r"\b(?:grep|rg|ripgrep)\b"), "Grep", "grep/rg"),
    (re.compile(r"\b(?:find|ls)\b"), "Glob", "find/ls"),
    (re.compile(r"\b(?:cat|head|tail)\b"), "Read", "cat/head/tail"),
    (re.compile(r"\bsed\s+-i\b"), "Edit", "sed -i"),
    (re.compile(r"\becho\s+.*>\s*\S+"), "Write", "echo >"),
]

# Patterns to strip for normalization
_VAR_ARGS = re.compile(
    r'(?:"[^"]*"|\'[^\']*\')'          # quoted strings
    r'|(?:/\S+)'                         # file paths
    r'|(?:\b\d+\.\d+[\.\d]*\b)'         # version numbers
    r'|(?:--\w[\w-]+=\S*)'              # --flag=value
)


def normalize_command(cmd: str) -> str:
    """Strip variable arguments, keeping the executable + subcommand."""
    cmd = cmd.strip()
    # Replace variable parts with *
    normed = _VAR_ARGS.sub("*", cmd)
    # Collapse multiple spaces/stars
    normed = re.sub(r"\s+", " ", normed).strip()
    normed = re.sub(r"\*(\s+\*)+", "*", normed)
    return normed


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
    project_dir = data_dir / "projects" / project_key
    cursor_path = data_dir / "cursors" / f"{project_key}.json"

    cursor = load_cursor(cursor_path)
    since_ts = parse_since(args.since) if args.since else None
    last_review = since_ts or cursor.get("last_permissions_review", "")

    records = load_jsonl(project_dir / "permissions.jsonl")
    total = len(records)

    new_records = [r for r in records if r.get("timestamp", "") > last_review] if last_review else records
    new_count = len(new_records)

    timestamps = [r.get("timestamp", "") for r in records if r.get("timestamp")]
    earliest = min(timestamps) if timestamps else ""
    latest = max(timestamps) if timestamps else ""

    # Group by normalized pattern
    by_pattern: dict[str, dict] = defaultdict(lambda: {
        "sessions": set(), "count": 0, "last_seen": "", "raw_commands": []
    })

    native_hits: dict[str, dict] = defaultdict(lambda: {"sessions": set(), "bash_cmd": "", "native_tool": ""})

    for r in records:
        tool_name = r.get("tool_name", "")
        tool_input = r.get("tool_input", {})
        session_id = r.get("session_id", "")
        ts = r.get("timestamp", "")

        # Get the command string
        if tool_name == "Bash":
            cmd = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
        else:
            cmd = tool_name

        pattern = normalize_command(cmd) if cmd else tool_name
        key = f"{tool_name}:{pattern}"

        by_pattern[key]["sessions"].add(session_id)
        by_pattern[key]["count"] += 1
        by_pattern[key]["last_seen"] = max(by_pattern[key]["last_seen"], ts)
        by_pattern[key]["raw_commands"].append(cmd[:100])
        by_pattern[key]["tool_name"] = tool_name
        by_pattern[key]["normalized_pattern"] = pattern

        # Check for native tool substitutions
        if tool_name == "Bash" and cmd:
            for native_re, native_tool, label in NATIVE_TOOLS:
                if native_re.search(cmd):
                    native_hits[label]["sessions"].add(session_id)
                    native_hits[label]["bash_cmd"] = label
                    native_hits[label]["native_tool"] = native_tool
                    break

    # Build pattern list, mark allow-list candidates (3+ sessions)
    patterns = []
    for key, info in by_pattern.items():
        session_list = sorted(info["sessions"])
        patterns.append({
            "key": key,
            "tool_name": info.get("tool_name", ""),
            "normalized_pattern": info.get("normalized_pattern", ""),
            "session_count": len(session_list),
            "sessions": session_list,
            "count": info["count"],
            "last_seen": info["last_seen"],
            "raw_commands": list(dict.fromkeys(info["raw_commands"]))[:5],
            "allow_list_candidate": len(session_list) >= 3,
        })

    patterns.sort(key=lambda p: p["session_count"], reverse=True)

    native_list = []
    for label, info in native_hits.items():
        native_list.append({
            "bash_cmd": info["bash_cmd"],
            "native_tool": info["native_tool"],
            "session_count": len(info["sessions"]),
            "sessions": sorted(info["sessions"]),
        })
    native_list.sort(key=lambda x: x["session_count"], reverse=True)

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total": total,
        "new_since_review": new_count,
        "last_review": last_review,
        "earliest": earliest,
        "latest": latest,
        "patterns": patterns,
        "native_tool_candidates": [n for n in native_list if n["session_count"] >= 2],
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "total": 0, "patterns": []}))
    sys.exit(0)
