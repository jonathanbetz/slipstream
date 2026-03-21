# /slipstream-health

Run a health check on the Slipstream installation. Verify that all hooks are installed,
executable, and registered — and that data files are intact. Report any issues with
suggested fixes.

---

## Step 1: Check prerequisites

Run these checks:

```bash
# jq available?
command -v jq >/dev/null 2>&1 && echo "OK" || echo "MISSING"

# hooks directory exists?
[ -d ~/.claude/hooks ] && echo "OK" || echo "MISSING"

# Each hook script present and executable?
for f in \
  slipstream-lib.sh \
  slipstream-thresholds.sh \
  slipstream-capture-permission.sh \
  slipstream-capture-compaction.sh \
  slipstream-capture-errors.sh \
  slipstream-capture-reads.sh \
  slipstream-check-triggers.sh \
  slipstream-session-start.sh; do
  path="$HOME/.claude/hooks/$f"
  if [ ! -f "$path" ]; then
    echo "MISSING: $f"
  elif [ ! -x "$path" ]; then
    echo "NOT EXECUTABLE: $f"
  else
    echo "OK: $f"
  fi
done
```

## Step 2: Check hook registration in settings.json

Read `~/.claude/settings.json`. Verify all six hook entries are registered with the
correct absolute paths (not relative paths):

- `PermissionRequest`  → `~/.claude/hooks/slipstream-capture-permission.sh`
- `PreCompact`         → `~/.claude/hooks/slipstream-capture-compaction.sh`
- `PostToolUseFailure` → `~/.claude/hooks/slipstream-capture-errors.sh`
- `PostToolUse`        → `~/.claude/hooks/slipstream-capture-reads.sh` (matcher: `Read|Glob`)
- `Stop`               → `~/.claude/hooks/slipstream-check-triggers.sh`
- `SessionStart`       → `~/.claude/hooks/slipstream-session-start.sh`

Flag any hook registered with a relative path or missing entirely.

## Step 3: Check data files

For each data file, report: exists/missing, line count, date of most recent entry:

```bash
DATA="$HOME/.slipstream"
for f in permissions.jsonl compactions.jsonl errors.jsonl reads.jsonl; do
  if [ ! -f "$DATA/$f" ]; then
    echo "MISSING: $f"
  else
    lines=$(wc -l < "$DATA/$f" | tr -d ' ')
    last_ts=$(tail -1 "$DATA/$f" 2>/dev/null | jq -r '.timestamp // "unknown"' 2>/dev/null || echo "unknown")
    echo "OK: $f  ($lines lines, last: $last_ts)"
    # Validate last 5 lines are valid JSON
    tail -5 "$DATA/$f" | while IFS= read -r line; do
      echo "$line" | jq -e . >/dev/null 2>&1 || echo "  WARNING: invalid JSON line found in $f"
    done
  fi
done
```

Also check state and cursor files:

```bash
for f in .cursor.json corrections-state.json memory-state.json commands-state.json; do
  if [ ! -f "$DATA/$f" ]; then
    echo "MISSING: $f  (will be created on first run — OK)"
  elif ! jq -e . "$DATA/$f" >/dev/null 2>&1; then
    echo "CORRUPT: $f  (not valid JSON)"
  else
    echo "OK: $f"
  fi
done
```

Check `errors.log` (Slipstream's own internal error log — separate from errors.jsonl):

```bash
errlog="$HOME/.slipstream/errors.log"
if [ ! -f "$errlog" ]; then
  echo "OK: errors.log (does not exist — no internal errors recorded)"
elif [ "$(wc -l < "$errlog" | tr -d ' ')" -eq 0 ]; then
  echo "OK: errors.log (0 lines)"
else
  count=$(wc -l < "$errlog" | tr -d ' ')
  echo "WARNING: errors.log has $count entries — recent slipstream hook failures:"
  tail -5 "$errlog"
fi
```

Check backups directory:

```bash
backup_dir="$HOME/.slipstream/backups"
if [ -d "$backup_dir" ]; then
  count=$(find "$backup_dir" -name '*.bak' 2>/dev/null | wc -l | tr -d ' ')
  echo "OK: backups/ ($count backup files)"
else
  echo "MISSING: backups/ (will be created on first apply — OK)"
fi
```

## Step 4: Print report

Print a structured health report:

```
Slipstream health check
════════════════════════════════════════════════════════════════

  Prerequisites:
    jq installed                    OK
    hooks directory exists          OK

  Hook files:
    slipstream-lib.sh               OK
    slipstream-thresholds.sh        OK
    slipstream-capture-permission   OK
    slipstream-capture-compaction   OK
    slipstream-capture-errors       OK
    slipstream-capture-reads        OK
    slipstream-check-triggers       OK
    slipstream-session-start        OK

  Hook registration (settings.json):
    PermissionRequest               OK
    PreCompact                      OK
    PostToolUseFailure              OK
    PostToolUse (Read|Glob)         OK
    Stop                            OK
    SessionStart                    OK

  Data files:
    permissions.jsonl               47 lines, last: 2026-03-19T12:00:00Z
    compactions.jsonl                9 lines, last: 2026-03-18T08:30:00Z
    errors.jsonl                    21 lines, last: 2026-03-20T17:45:00Z
    reads.jsonl                    112 lines, last: 2026-03-21T09:10:00Z
    .cursor.json                    OK
    corrections-state.json          OK (12 analyzed sessions)
    memory-state.json               MISSING (OK — will be created on first run)
    commands-state.json             OK (8 analyzed sessions)
    errors.log                      0 lines (no internal errors)
    backups/                        3 backup files

  Overall: HEALTHY
```

If any item is not OK, list it under **Issues found:** with a suggested fix:

```
  Issues found:
    slipstream-capture-reads.sh is not executable
      Fix: chmod +x ~/.claude/hooks/slipstream-capture-reads.sh

    PostToolUse hook is not registered in settings.json
      Fix: run ./install.sh from the slipstream repo to re-register hooks

    errors.log has 5 entries (hook failures detected)
      Fix: review ~/.slipstream/errors.log for details; re-install if jq path changed
```

If all checks pass, say:

> All checks passed. Slipstream is healthy.
