#!/usr/bin/env python3
# slipstream-capture-reads.py
# Fires on PostToolUse for Read and Glob tools. Logs the file path only —
# never captures file contents.

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from slipstream import lib

try:
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)

    data = lib.validate_json(raw, "slipstream-capture-reads")
    if data is None:
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name not in ("Read", "Glob"):
        sys.exit(0)

    cwd = data.get("cwd", "")
    if not cwd:
        sys.exit(0)

    tool_input = data.get("tool_input", {})
    if tool_name == "Read":
        file_path = tool_input.get("file_path", "")
    else:
        file_path = tool_input.get("pattern", "")

    if not file_path:
        sys.exit(0)

    project_key = lib.project_key_for(cwd)
    log = lib.DATA_DIR / "projects" / project_key / "reads.jsonl"

    lib.write_log(log, {
        "timestamp": lib.now_iso(),
        "session_id": data.get("session_id", ""),
        "cwd": cwd,
        "tool_name": tool_name,
        "file_path": file_path,
    })
except Exception:
    pass

sys.exit(0)
