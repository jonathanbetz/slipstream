#!/usr/bin/env python3
# slipstream-check-triggers.py
# Fires on Stop. Checks per-module thresholds for the CURRENT PROJECT only and
# prints specific commands to run when friction has accumulated enough.

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from slipstream import lib, thresholds

DATA_DIR = lib.DATA_DIR


def days_since(ts: str) -> int:
    """Return whole days elapsed since an ISO-8601 UTC timestamp."""
    if not ts:
        return 9999
    try:
        # datetime.fromisoformat handles 'Z' suffix in Python 3.11+; handle both
        ts_clean = ts.replace("Z", "+00:00")
        past = datetime.fromisoformat(ts_clean)
        delta = datetime.now(timezone.utc) - past
        return delta.days
    except Exception:
        return 9999


def count_new(jsonl: Path, last_ts: str) -> int:
    """Count JSONL lines with .timestamp strictly after last_ts."""
    if not jsonl.is_file():
        return 0
    last_ts = last_ts or "1970-01-01T00:00:00Z"
    count = 0
    try:
        with open(jsonl) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                    if record.get("timestamp", "") > last_ts:
                        count += 1
                except json.JSONDecodeError:
                    pass
    except Exception:
        pass
    return count


def load_cursor(cursor: Path) -> dict:
    if not cursor.is_file():
        return {}
    try:
        return json.loads(cursor.read_text())
    except Exception:
        return {}


def load_state(state_path: Path) -> set:
    """Return set of analyzed session IDs from a state file."""
    if not state_path.is_file():
        return set()
    try:
        data = json.loads(state_path.read_text())
        return set(data.get("analyzed_session_ids", []))
    except Exception:
        return set()


def count_unanalyzed(sessions_dir: Path, state_path: Path) -> int:
    if not sessions_dir.is_dir():
        return 0
    session_ids = {p.stem for p in sessions_dir.glob("*.jsonl")}
    analyzed = load_state(state_path)
    unanalyzed = max(0, len(session_ids - analyzed))
    return unanalyzed


try:
    raw = sys.stdin.read()
    data = {}
    if raw.strip():
        try:
            data = json.loads(raw)
        except Exception:
            pass

    cwd = data.get("cwd", "") or str(Path.cwd())
    project_key = lib.project_key_for(cwd)

    project_dir = DATA_DIR / "projects" / project_key
    project_dir.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "cursors").mkdir(parents=True, exist_ok=True)

    cursor = load_cursor(DATA_DIR / "cursors" / f"{project_key}.json")

    last_permissions_ts = cursor.get("last_permissions_review", "")
    last_context_ts     = cursor.get("last_context_review", "")
    last_errors_ts      = cursor.get("last_errors_review", "")
    last_reads_ts       = cursor.get("last_reads_review", "")
    last_corrections_ts = cursor.get("last_corrections_review", "")
    last_memory_ts      = cursor.get("last_memory_review", "")
    last_commands_ts    = cursor.get("last_commands_review", "")

    new_permissions = count_new(project_dir / "permissions.jsonl", last_permissions_ts)
    new_compactions = count_new(project_dir / "compactions.jsonl", last_context_ts)
    new_errors      = count_new(project_dir / "errors.jsonl",      last_errors_ts)
    new_reads       = count_new(project_dir / "reads.jsonl",        last_reads_ts)

    sessions_dir = Path.home() / ".claude" / "projects" / project_key
    unanalyzed_corrections = count_unanalyzed(sessions_dir, DATA_DIR / "corrections-state.json")
    unanalyzed_memory      = count_unanalyzed(sessions_dir, DATA_DIR / "memory-state.json")
    unanalyzed_commands    = count_unanalyzed(sessions_dir, DATA_DIR / "commands-state.json")

    recommendations: list[str] = []

    def should_include(new: int, threshold: int, last_ts: str) -> bool:
        if new >= threshold:
            return True
        if new > 0 and last_ts and days_since(last_ts) >= thresholds.TIME_DAYS:
            return True
        return False

    if should_include(new_permissions, thresholds.PERMISSIONS, last_permissions_ts):
        recommendations.append(f"/slipstream-permissions ({new_permissions} allow-list candidates)")

    if should_include(new_compactions, thresholds.COMPACTIONS, last_context_ts):
        recommendations.append(f"/slipstream-context ({new_compactions} compactions)")

    if should_include(new_errors, thresholds.ERRORS, last_errors_ts):
        recommendations.append(f"/slipstream-errors ({new_errors} tool failures)")

    if should_include(new_reads, thresholds.READS, last_reads_ts):
        recommendations.append(f"/slipstream-reads ({new_reads} orientation reads)")

    if should_include(unanalyzed_corrections, thresholds.CORRECTIONS, last_corrections_ts):
        recommendations.append(f"/slipstream-corrections ({unanalyzed_corrections} sessions to mine)")

    if should_include(unanalyzed_memory, thresholds.MEMORY, last_memory_ts):
        recommendations.append(f"/slipstream-memory ({unanalyzed_memory} sessions to mine)")

    if should_include(unanalyzed_commands, thresholds.COMMANDS, last_commands_ts):
        recommendations.append(f"/slipstream-commands ({unanalyzed_commands} sessions to mine)")

    if recommendations:
        print("[Slipstream] Ready: " + " · ".join(recommendations))

except Exception:
    pass

sys.exit(0)
