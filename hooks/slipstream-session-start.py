#!/usr/bin/env python3
# slipstream-session-start.py
# Fires on SessionStart. Silent: ensures the per-project data directory exists.

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from slipstream import lib

try:
    raw = sys.stdin.read()
    data = lib.validate_json(raw, "slipstream-session-start") if raw.strip() else {}
    cwd = (data or {}).get("cwd", "") if data else ""
    if not cwd:
        cwd = str(Path.cwd())
    project_key = lib.project_key_for(cwd)
    (lib.DATA_DIR / "projects" / project_key).mkdir(parents=True, exist_ok=True)
    (lib.DATA_DIR / "cursors").mkdir(parents=True, exist_ok=True)
except Exception:
    pass

sys.exit(0)
