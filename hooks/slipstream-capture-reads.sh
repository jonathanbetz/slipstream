#!/bin/bash
# slipstream-capture-reads.sh
# Fires on PostToolUse for Read and Glob tools. Logs the file path only —
# never captures file contents.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
LOG="$DATA_DIR/reads.jsonl"

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

# Shared utilities (write_log, log_error, validate_json)
# shellcheck source=slipstream-lib.sh
. "$(dirname "$0")/slipstream-lib.sh"

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Validate JSON before extracting fields; logs to errors.log on failure
_slipstream_validate_json "$INPUT" "$(basename "$0")"

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"

# Only log Read and Glob tool uses
case "$TOOL_NAME" in
  Read|Glob) ;;
  *) exit 0 ;;
esac

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
[ -z "$CWD" ] && exit 0

PROJECT_KEY="$(printf '%s' "$CWD" | sed 's|/|-|g')"
LOG="$DATA_DIR/projects/$PROJECT_KEY/reads.jsonl"
mkdir -p "$DATA_DIR/projects/$PROJECT_KEY"

# Read uses file_path; Glob uses pattern
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')"
else
  FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // ""')"
fi

[ -z "$FILE_PATH" ] && exit 0

_slipstream_write_log "$LOG" "$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg tool "$TOOL_NAME" \
  --arg fp "$FILE_PATH" \
  '{timestamp: $ts, session_id: $sid, cwd: $cwd, tool_name: $tool, file_path: $fp}')"

exit 0
