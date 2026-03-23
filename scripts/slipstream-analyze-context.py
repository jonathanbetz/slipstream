#!/usr/bin/env python3
"""
slipstream-analyze-context.py
Reads the compactions JSONL for the current project, groups by session,
and flags high-compaction sessions. Outputs JSON to stdout.

Usage: python3 slipstream-analyze-context.py [--cwd PATH]
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path


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
    last_review = cursor.get("last_context_review", "")

    records = load_jsonl(project_dir / "compactions.jsonl")
    total = len(records)
    new_count = sum(1 for r in records if r.get("timestamp", "") > last_review) if last_review else total

    by_session: dict[str, dict] = defaultdict(lambda: {"timestamps": [], "cwds": set()})
    for r in records:
        sid = r.get("session_id", "unknown")
        by_session[sid]["timestamps"].append(r.get("timestamp", ""))
        if r.get("cwd"):
            by_session[sid]["cwds"].add(r["cwd"])

    sessions = []
    for sid, info in by_session.items():
        ts = sorted(info["timestamps"])
        count = len(ts)
        sessions.append({
            "session_id": sid,
            "count": count,
            "first": ts[0] if ts else "",
            "last": ts[-1] if ts else "",
            "cwds": sorted(info["cwds"]),
            "multi_compaction": count >= 2,
        })

    sessions.sort(key=lambda s: s["count"], reverse=True)

    high_compaction_sessions = [s["session_id"] for s in sessions if s["count"] >= 2]

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total": total,
        "new_since_review": new_count,
        "last_review": last_review,
        "distinct_sessions": len(sessions),
        "sessions": sessions,
        "high_compaction_sessions": high_compaction_sessions,
        "has_high_compaction": total >= 3 or bool(high_compaction_sessions),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "total": 0, "sessions": []}))
    sys.exit(0)
