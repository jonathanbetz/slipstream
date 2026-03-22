#!/usr/bin/env python3
# slipstream-capture-errors.py
# Fires on PostToolUseFailure events. Logs the failure without capturing
# tool_response content (keeps logs small).

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from slipstream import lib

try:
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)

    data = lib.validate_json(raw, "slipstream-capture-errors")
    if data is None:
        sys.exit(0)

    cwd = data.get("cwd", "")
    if not cwd:
        sys.exit(0)

    project_key = lib.project_key_for(cwd)
    log = lib.DATA_DIR / "projects" / project_key / "errors.jsonl"

    # Deliberately omit tool_response to keep logs small
    lib.write_log(log, {
        "timestamp": lib.now_iso(),
        "session_id": data.get("session_id", ""),
        "cwd": cwd,
        "tool_name": data.get("tool_name", ""),
        "tool_input": data.get("tool_input", {}),
    })
except Exception:
    pass

sys.exit(0)
