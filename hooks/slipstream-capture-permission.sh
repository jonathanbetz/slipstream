#!/bin/bash
# slipstream-capture-permission.sh
# Fires on PermissionRequest events. Logs the event and exits 0 so Claude Code
# continues showing its normal permission dialog unchanged.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
LOG="$DATA_DIR/permissions.jsonl"

# Never block Claude Code — exit 0 on any error
trap 'exit 0' ERR

# Require jq
command -v jq >/dev/null 2>&1 || exit 0

# Shared utilities (write_log, log_error, validate_json)
# shellcheck source=slipstream-lib.sh
. "$(dirname "$0")/slipstream-lib.sh"

# Read stdin
INPUT="$(cat)"
[ -z "$INPUT" ] && exit 0

# Validate JSON before extracting fields; logs to errors.log on failure
_slipstream_validate_json "$INPUT" "$(basename "$0")"

mkdir -p "$DATA_DIR"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // ""')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
TOOL_INPUT="$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')"

_slipstream_write_log "$LOG" "$(jq -cn \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg tool "$TOOL_NAME" \
  --argjson input "$TOOL_INPUT" \
  '{timestamp: $ts, session_id: $sid, cwd: $cwd, tool_name: $tool, tool_input: $input}')"

exit 0
