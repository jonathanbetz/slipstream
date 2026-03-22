# slipstream/lib.py — shared utilities for all slipstream hooks.
# stdlib only: json, fcntl, pathlib, datetime, sys

from __future__ import annotations

import fcntl
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


DATA_DIR = Path.home() / ".slipstream"


def project_key_for(cwd: str) -> str:
    """Encode a cwd path as a project key: /Users/alice/src/app → -Users-alice-src-app"""
    return cwd.replace("/", "-")


def now_iso() -> str:
    """Return the current UTC time as an ISO-8601 string."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_log(log: Path, record: dict) -> None:
    """Thread-safe JSONL append using fcntl.flock."""
    log.parent.mkdir(parents=True, exist_ok=True)
    lock_path = Path(str(log) + ".lock")
    with open(lock_path, "w") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        with open(log, "a") as fh:
            fh.write(json.dumps(record) + "\n")


def log_error(message: str) -> None:
    """Append a timestamped error to ~/.slipstream/errors.log (plain text)."""
    err_log = DATA_DIR / "errors.log"
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    ts = now_iso()
    try:
        with open(err_log, "a") as fh:
            fh.write(f"{ts} [slipstream] {message}\n")
    except Exception:
        pass


def validate_json(raw: str, script_name: str) -> dict | None:
    """Parse JSON string; on failure logs to errors.log and returns None."""
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        log_error(f"{script_name}: malformed JSON input: {exc}")
        return None
