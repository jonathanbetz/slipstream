#!/bin/bash
# slipstream-lib.sh — shared utilities sourced by all slipstream hooks.
# Do not execute directly; source with: . "$(dirname "$0")/slipstream-lib.sh"

# Write a JSON line to a log file, using flock when available to protect
# against concurrent writes from multiple simultaneous Claude Code sessions.
# Usage: _slipstream_write_log <log_file> <json_line>
_slipstream_write_log() {
  local log="$1"
  local line="$2"
  local lock="${log}.lock"
  if command -v flock >/dev/null 2>&1; then
    ( flock -x 200; printf '%s\n' "$line" >> "$log" ) 200>"$lock"
  else
    printf '%s\n' "$line" >> "$log"
  fi
}

# Log a slipstream-internal error to ~/.slipstream/errors.log (plain text,
# separate from errors.jsonl which tracks tool failures).
# Usage: _slipstream_log_error <message>
_slipstream_log_error() {
  local msg="$1"
  local errlog="$HOME/.slipstream/errors.log"
  mkdir -p "$HOME/.slipstream" 2>/dev/null || true
  printf '%s [slipstream] %s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)" "$msg" \
    >> "$errlog" 2>/dev/null || true
}

# Validate that a string is valid JSON. On failure, logs to errors.log and
# exits 0 (never blocks Claude Code).
# Usage: _slipstream_validate_json <input_string> <script_name>
_slipstream_validate_json() {
  local input="$1"
  local script="$2"
  local err
  if ! err="$(printf '%s' "$input" | jq -c '.' 2>&1 >/dev/null)"; then
    _slipstream_log_error "$script: malformed JSON input: $err"
    exit 0
  fi
}
