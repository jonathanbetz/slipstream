#!/bin/bash
# slipstream-capture-compaction.sh
# Fires on PreCompact events. Logs the event silently.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
LOG="$DATA_DIR/compactions.jsonl"

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

mkdir -p "$DATA_DIR"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"

printf '%s\n' "$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg cwd "$CWD" \
  '{timestamp: $ts, session_id: $sid, cwd: $cwd}'
)" >> "$LOG"

exit 0
