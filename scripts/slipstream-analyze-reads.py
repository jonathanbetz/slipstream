#!/usr/bin/env python3
from __future__ import annotations
"""
slipstream-analyze-reads.py
Reads the reads JSONL for the current project, groups by file path,
and identifies orientation files (read in 3+ distinct sessions).
Outputs JSON to stdout.

Usage: python3 slipstream-analyze-reads.py [--cwd PATH]
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


def file_priority(file_path: str) -> int:
    """Lower number = higher priority in display order."""
    p = file_path.lower()
    if "claude.md" in p:
        return 0
    if "readme" in p:
        return 1
    if any(w in p for w in ("architecture", "design", "spec", "docs/")):
        return 2
    if any(w in p for w in (".env", "config", "settings")):
        return 3
    return 4


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
    last_review = cursor.get("last_reads_review", "")

    records = load_jsonl(project_dir / "reads.jsonl")
    total = len(records)
    new_count = sum(1 for r in records if r.get("timestamp", "") > last_review) if last_review else total

    by_file: dict[str, dict] = defaultdict(lambda: {"sessions": set(), "tool_names": set()})

    for r in records:
        fp = r.get("file_path", "")
        if not fp:
            continue
        by_file[fp]["sessions"].add(r.get("session_id", ""))
        by_file[fp]["tool_names"].add(r.get("tool_name", ""))

    distinct_files = len(by_file)

    orientation_files = []
    for fp, info in by_file.items():
        session_list = sorted(info["sessions"])
        if len(session_list) >= 3:
            orientation_files.append({
                "file_path": fp,
                "session_count": len(session_list),
                "sessions": session_list,
                "tool_names": sorted(info["tool_names"]),
                "priority": file_priority(fp),
            })

    orientation_files.sort(key=lambda f: (f["priority"], -f["session_count"]))

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "total": total,
        "new_since_review": new_count,
        "last_review": last_review,
        "distinct_files": distinct_files,
        "orientation_files": orientation_files,
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "total": 0, "orientation_files": []}))
    sys.exit(0)
