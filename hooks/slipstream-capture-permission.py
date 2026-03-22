#!/usr/bin/env python3
# slipstream-capture-permission.py
# Fires on PermissionRequest events. Logs the event and exits 0 so Claude Code
# continues showing its normal permission dialog unchanged.

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from slipstream import lib

try:
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)

    data = lib.validate_json(raw, "slipstream-capture-permission")
    if data is None:
        sys.exit(0)

    cwd = data.get("cwd", "")
    if not cwd:
        sys.exit(0)

    project_key = lib.project_key_for(cwd)
    log = lib.DATA_DIR / "projects" / project_key / "permissions.jsonl"

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
