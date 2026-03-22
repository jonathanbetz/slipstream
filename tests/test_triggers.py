"""Tests for slipstream-check-triggers.py threshold logic."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

HOOKS_DIR = Path(__file__).parent.parent / "hooks"


def run_triggers(home: Path, stdin: str = "") -> subprocess.CompletedProcess:
    env = {**os.environ, "HOME": str(home)}
    return subprocess.run(
        [sys.executable, str(HOOKS_DIR / "slipstream-check-triggers.py")],
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
    )


def write_permission_events(home: Path, project_key: str, n: int, base_ts: str = "2026-01-01T00:00:00Z"):
    log = home / ".slipstream" / "projects" / project_key / "permissions.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "w") as fh:
        for i in range(n):
            fh.write(json.dumps({
                "timestamp": f"2026-01-01T00:00:{i:02d}Z",
                "session_id": f"s{i}",
                "cwd": "/tmp",
                "tool_name": "Bash",
                "tool_input": {},
            }) + "\n")


def write_error_events(home: Path, project_key: str, n: int):
    log = home / ".slipstream" / "projects" / project_key / "errors.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "w") as fh:
        for i in range(n):
            fh.write(json.dumps({
                "timestamp": f"2026-01-01T00:00:{i:02d}Z",
                "session_id": f"s{i}",
                "cwd": "/tmp",
                "tool_name": "Bash",
                "tool_input": {},
            }) + "\n")


# ── basic behavior ────────────────────────────────────────────────────────────

def test_exits_0_no_data(tmp_path):
    (tmp_path / ".slipstream").mkdir()
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert result.returncode == 0


def test_no_output_when_no_data(tmp_path):
    (tmp_path / ".slipstream").mkdir()
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert result.stdout.strip() == ""


# ── thresholds module ─────────────────────────────────────────────────────────

def test_thresholds_defines_all_constants():
    import slipstream.thresholds as t
    assert isinstance(t.PERMISSIONS, int)
    assert isinstance(t.COMPACTIONS, int)
    assert isinstance(t.ERRORS, int)
    assert isinstance(t.READS, int)
    assert isinstance(t.CORRECTIONS, int)
    assert isinstance(t.MEMORY, int)
    assert isinstance(t.COMMANDS, int)
    assert isinstance(t.TIME_DAYS, int)


# ── permission threshold ──────────────────────────────────────────────────────

def test_permissions_below_threshold_no_recommendation(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", t.PERMISSIONS - 1)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-permissions" not in result.stdout


def test_permissions_at_threshold_recommendation(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", t.PERMISSIONS)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-permissions" in result.stdout


def test_permissions_above_threshold_recommendation(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", t.PERMISSIONS + 5)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-permissions" in result.stdout


# ── errors threshold ──────────────────────────────────────────────────────────

def test_errors_below_threshold_no_recommendation(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_error_events(tmp_path, "-tmp", t.ERRORS - 1)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-errors" not in result.stdout


def test_errors_at_threshold_recommendation(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_error_events(tmp_path, "-tmp", t.ERRORS)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-errors" in result.stdout


# ── time-based trigger ────────────────────────────────────────────────────────

def test_time_based_trigger_fires_after_threshold_days(tmp_path):
    """1 new event + last review > TIME_DAYS ago → triggers."""
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", 1)

    # Set cursor with a very old last review
    cursor_dir = tmp_path / ".slipstream" / "cursors"
    cursor_dir.mkdir(parents=True, exist_ok=True)
    cursor = cursor_dir / "-tmp.json"
    cursor.write_text(json.dumps({
        "last_permissions_review": "2020-01-01T00:00:00Z",
    }))

    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-permissions" in result.stdout


def test_time_based_trigger_does_not_fire_if_recent(tmp_path):
    """1 new event + last review yesterday → no trigger."""
    import slipstream.thresholds as t
    from datetime import datetime, timezone, timedelta

    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", 1)

    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    cursor_dir = tmp_path / ".slipstream" / "cursors"
    cursor_dir.mkdir(parents=True, exist_ok=True)
    cursor = cursor_dir / "-tmp.json"
    cursor.write_text(json.dumps({
        "last_permissions_review": yesterday,
    }))

    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert "/slipstream-permissions" not in result.stdout


# ── output format ─────────────────────────────────────────────────────────────

def test_output_starts_with_slipstream_ready(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", t.PERMISSIONS)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert result.stdout.startswith("[Slipstream] Ready:")


def test_multiple_recommendations_joined_with_dot(tmp_path):
    import slipstream.thresholds as t
    (tmp_path / ".slipstream").mkdir()
    write_permission_events(tmp_path, "-tmp", t.PERMISSIONS)
    write_error_events(tmp_path, "-tmp", t.ERRORS)
    result = run_triggers(tmp_path, stdin='{"cwd":"/tmp"}')
    assert " · " in result.stdout
