"""Integration tests for capture hook scripts (run as subprocesses)."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

HOOKS_DIR = Path(__file__).parent.parent / "hooks"
FIXTURES_DIR = Path(__file__).parent / "fixtures"


def run_hook(script: str, fixture: str, home: Path) -> subprocess.CompletedProcess:
    env = {**os.environ, "HOME": str(home)}
    with open(FIXTURES_DIR / fixture) as fh:
        return subprocess.run(
            [sys.executable, str(HOOKS_DIR / script)],
            stdin=fh,
            capture_output=True,
            text=True,
            env=env,
        )


# ── capture-permission ────────────────────────────────────────────────────────

def test_permission_exits_0(tmp_path):
    result = run_hook("slipstream-capture-permission.py", "valid-permission.json", tmp_path)
    assert result.returncode == 0


def test_permission_writes_one_valid_line(tmp_path):
    run_hook("slipstream-capture-permission.py", "valid-permission.json", tmp_path)
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "permissions.jsonl"
    assert log.is_file()
    lines = log.read_text().splitlines()
    assert len(lines) == 1
    json.loads(lines[0])  # must be valid JSON


def test_permission_has_required_fields(tmp_path):
    run_hook("slipstream-capture-permission.py", "valid-permission.json", tmp_path)
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "permissions.jsonl"
    record = json.loads(log.read_text().strip())
    for field in ("timestamp", "session_id", "cwd", "tool_name", "tool_input"):
        assert field in record, f"missing field: {field}"


def test_permission_malformed_exits_0(tmp_path):
    result = run_hook("slipstream-capture-permission.py", "malformed.json", tmp_path)
    assert result.returncode == 0


def test_permission_malformed_writes_errors_log(tmp_path):
    run_hook("slipstream-capture-permission.py", "malformed.json", tmp_path)
    err_log = tmp_path / ".slipstream" / "errors.log"
    assert err_log.is_file()
    assert "slipstream-capture-permission" in err_log.read_text()


def test_permission_malformed_does_not_write_jsonl(tmp_path):
    run_hook("slipstream-capture-permission.py", "malformed.json", tmp_path)
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "permissions.jsonl"
    assert not log.is_file() or log.stat().st_size == 0


# ── capture-compaction ────────────────────────────────────────────────────────

def test_compaction_exits_0_and_writes_valid_json(tmp_path):
    result = run_hook("slipstream-capture-compaction.py", "valid-compaction.json", tmp_path)
    assert result.returncode == 0
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "compactions.jsonl"
    assert log.is_file()
    assert len(log.read_text().splitlines()) == 1
    json.loads(log.read_text().strip())


def test_compaction_malformed_exits_0(tmp_path):
    result = run_hook("slipstream-capture-compaction.py", "malformed.json", tmp_path)
    assert result.returncode == 0


# ── capture-errors ────────────────────────────────────────────────────────────

def test_errors_exits_0_and_writes_valid_json(tmp_path):
    result = run_hook("slipstream-capture-errors.py", "valid-error.json", tmp_path)
    assert result.returncode == 0
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "errors.jsonl"
    assert log.is_file()
    assert len(log.read_text().splitlines()) == 1
    json.loads(log.read_text().strip())


def test_errors_malformed_exits_0(tmp_path):
    result = run_hook("slipstream-capture-errors.py", "malformed.json", tmp_path)
    assert result.returncode == 0


# ── capture-reads ─────────────────────────────────────────────────────────────

def test_reads_logs_read_tool(tmp_path):
    run_hook("slipstream-capture-reads.py", "valid-reads-read.json", tmp_path)
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "reads.jsonl"
    assert log.is_file()
    record = json.loads(log.read_text().strip())
    assert "file_path" in record


def test_reads_logs_glob_tool(tmp_path):
    run_hook("slipstream-capture-reads.py", "valid-reads-glob.json", tmp_path)
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "reads.jsonl"
    assert log.is_file()
    record = json.loads(log.read_text().strip())
    assert "file_path" in record


def test_reads_skips_other_tools(tmp_path):
    # valid-permission.json uses Bash tool — should not be logged
    run_hook("slipstream-capture-reads.py", "valid-permission.json", tmp_path)
    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "reads.jsonl"
    assert not log.is_file()


def test_reads_malformed_exits_0(tmp_path):
    result = run_hook("slipstream-capture-reads.py", "malformed.json", tmp_path)
    assert result.returncode == 0


# ── concurrent writes ─────────────────────────────────────────────────────────

def test_concurrent_writes_correct_line_count(tmp_path):
    """10 parallel permission captures must produce exactly 10 valid JSON lines."""
    import concurrent.futures

    def one_write(_):
        return run_hook("slipstream-capture-permission.py", "valid-permission.json", tmp_path)

    n = 10
    with concurrent.futures.ThreadPoolExecutor(max_workers=n) as pool:
        list(pool.map(one_write, range(n)))

    log = tmp_path / ".slipstream" / "projects" / "-Users-test-src-myapp" / "permissions.jsonl"
    lines = log.read_text().splitlines()
    assert len(lines) == n
    for line in lines:
        json.loads(line)
