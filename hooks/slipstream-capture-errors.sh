#!/bin/bash
# slipstream-capture-errors.sh
# Fires on PostToolUseFailure events. Logs the failure without capturing
# tool_response content (keeps logs small).

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
LOG="$DATA_DIR/errors.jsonl"

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

mkdir -p "$DATA_DIR"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
TOOL_INPUT="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')"

# Deliberately omit tool_response to keep logs small
printf '%s\n' "$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg tool "$TOOL_NAME" \
  --argjson input "$TOOL_INPUT" \
  '{timestamp: $ts, session_id: $sid, cwd: $cwd, tool_name: $tool, tool_input: $input}'
)" >> "$LOG"

exit 0
