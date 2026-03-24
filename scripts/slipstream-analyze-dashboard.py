#!/usr/bin/env python3
from __future__ import annotations
"""
slipstream-analyze-dashboard.py
Reads all per-project friction logs and state files for the current project
and outputs a structured JSON summary for the /slipstream dashboard.

Usage: python3 slipstream-analyze-dashboard.py [--cwd PATH] [--since DURATION]

DURATION examples: 7d, 6h, 30m — overrides cursor timestamps so all events
within that window appear as "new".
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


def project_key_for(cwd: str) -> str:
    return cwd.replace("/", "-")


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


def load_json(path: Path, default):
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def count_new(records: list[dict], last_ts: str) -> int:
    if not last_ts:
        return len(records)
    return sum(1 for r in records if r.get("timestamp", "") > last_ts)


def days_since(ts: str) -> int | None:
    if not ts:
        return None
    try:
        ts_clean = ts.replace("Z", "+00:00")
        past = datetime.fromisoformat(ts_clean)
        return (datetime.now(timezone.utc) - past).days
    except Exception:
        return None


def unanalyzed_count(sessions_dir: Path, state_path: Path) -> int:
    if not sessions_dir.is_dir():
        return 0
    all_ids = {p.stem for p in sessions_dir.glob("*.jsonl")}
    state = load_json(state_path, {"analyzed_session_ids": []})
    analyzed = set(state.get("analyzed_session_ids", []))
    return max(0, len(all_ids - analyzed))


def parse_since(value: str) -> str:
    """Parse a duration string like '7d', '6h', '30m' into an ISO timestamp."""
    m = re.fullmatch(r"(\d+)([dhm])", value.strip().lower())
    if not m:
        raise ValueError(f"Invalid --since value {value!r}. Use e.g. 7d, 6h, 30m.")
    amount, unit = int(m.group(1)), m.group(2)
    delta = {"d": timedelta(days=amount), "h": timedelta(hours=amount), "m": timedelta(minutes=amount)}[unit]
    cutoff = datetime.now(timezone.utc) - delta
    return cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--since", default=None,
                        help="Override cursors: treat events newer than this window as new (e.g. 7d, 6h, 30m)")
    args = parser.parse_args()

    cwd = args.cwd
    project_key = project_key_for(cwd)
    home = Path.home()
    data_dir = home / ".slipstream"
    project_dir = data_dir / "projects" / project_key
    cursor_path = data_dir / "cursors" / f"{project_key}.json"
    sessions_dir = home / ".claude" / "projects" / project_key

    cursor = load_json(cursor_path, {})

    # --since overrides all cursor timestamps
    since_ts = parse_since(args.since) if args.since else None

    permissions  = load_jsonl(project_dir / "permissions.jsonl")
    compactions  = load_jsonl(project_dir / "compactions.jsonl")
    errors       = load_jsonl(project_dir / "errors.jsonl")
    reads        = load_jsonl(project_dir / "reads.jsonl")

    last_permissions_ts = since_ts or cursor.get("last_permissions_review", "")
    last_context_ts     = since_ts or cursor.get("last_context_review", "")
    last_errors_ts      = since_ts or cursor.get("last_errors_review", "")
    last_reads_ts       = since_ts or cursor.get("last_reads_review", "")

    # Most recent review across all modules
    all_review_ts = [
        ts for ts in [
            last_permissions_ts, last_context_ts, last_errors_ts, last_reads_ts,
            cursor.get("last_corrections_review", ""),
            cursor.get("last_memory_review", ""),
            cursor.get("last_commands_review", ""),
        ] if ts
    ]
    last_review_ts = max(all_review_ts) if all_review_ts else ""
    last_review_days = days_since(last_review_ts)

    def module_stats(records, last_ts):
        return {
            "total": len(records),
            "new": count_new(records, last_ts),
            "sessions": len({r.get("session_id") for r in records if r.get("session_id")}),
        }

    result = {
        "project_key": project_key,
        "project_cwd": cwd,
        "last_review_ts": last_review_ts,
        "last_review_days": last_review_days,
        "modules": {
            "permissions": module_stats(permissions, last_permissions_ts),
            "context":     module_stats(compactions, last_context_ts),
            "errors":      module_stats(errors, last_errors_ts),
            "reads":       module_stats(reads, last_reads_ts),
            "corrections": {"unanalyzed": unanalyzed_count(sessions_dir, data_dir / "corrections-state.json")},
            "memory":      {"unanalyzed": unanalyzed_count(sessions_dir, data_dir / "memory-state.json")},
            "commands":    {"unanalyzed": unanalyzed_count(sessions_dir, data_dir / "commands-state.json")},
        },
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"error": str(exc), "modules": {}}))
    sys.exit(0)
