#!/bin/bash
# slipstream-capture-compaction.sh
# Fires on PreCompact events. Logs the event silently.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
LOG="$DATA_DIR/compactions.jsonl"

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

# Shared utilities (write_log, log_error, validate_json)
# shellcheck source=slipstream-lib.sh
. "$(dirname "$0")/slipstream-lib.sh"

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Validate JSON before extracting fields; logs to errors.log on failure
_slipstream_validate_json "$INPUT" "$(basename "$0")"

mkdir -p "$DATA_DIR"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"

_slipstream_write_log "$LOG" "$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg cwd "$CWD" \
  '{timestamp: $ts, session_id: $sid, cwd: $cwd}')"

exit 0
