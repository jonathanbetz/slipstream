#!/bin/bash
# slipstream-check-triggers.sh
# Fires on Stop and SessionStart. Checks whether the user should run /slipstream
# based on event count threshold (20) or time elapsed since last review (7 days).

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
CURSOR="$DATA_DIR/.cursor.json"
THRESHOLD=20
TIME_THRESHOLD_DAYS=7
TIME_EVENT_MIN=5

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$DATA_DIR"

# Read cursor state
LAST_PERMISSIONS=0
LAST_COMPACTIONS=0
LAST_ERRORS=0
LAST_REVIEW_TS=""

if [ -f "$CURSOR" ]; then
  LAST_PERMISSIONS="$(jq -r '.permissions_line_count // 0' "$CURSOR")"
  LAST_COMPACTIONS="$(jq -r '.compactions_line_count // 0' "$CURSOR")"
  LAST_ERRORS="$(jq -r '.errors_line_count // 0' "$CURSOR")"
  LAST_REVIEW_TS="$(jq -r '.last_review_timestamp // ""' "$CURSOR")"
fi

# Count current lines in each log
count_lines() {
  local f="$1"
  if [ -f "$f" ]; then
    wc -l < "$f" | tr -d ' '
  else
    echo 0
  fi
}

CUR_PERMISSIONS="$(count_lines "$DATA_DIR/permissions.jsonl")"
CUR_COMPACTIONS="$(count_lines "$DATA_DIR/compactions.jsonl")"
CUR_ERRORS="$(count_lines "$DATA_DIR/errors.jsonl")"

NEW_PERMISSIONS=$(( CUR_PERMISSIONS - LAST_PERMISSIONS ))
NEW_COMPACTIONS=$(( CUR_COMPACTIONS - LAST_COMPACTIONS ))
NEW_ERRORS=$(( CUR_ERRORS - LAST_ERRORS ))

# Guard against negative values (e.g. log rotation)
[ "$NEW_PERMISSIONS" -lt 0 ] && NEW_PERMISSIONS=0
[ "$NEW_COMPACTIONS" -lt 0 ] && NEW_COMPACTIONS=0
[ "$NEW_ERRORS" -lt 0 ] && NEW_ERRORS=0

TOTAL_NEW=$(( NEW_PERMISSIONS + NEW_COMPACTIONS + NEW_ERRORS ))

# Check threshold trigger
if [ "$TOTAL_NEW" -ge "$THRESHOLD" ]; then
  echo "[Slipstream] $TOTAL_NEW new friction events captured. Run /slipstream to review and reduce them."
  exit 0
fi

# Check time-based trigger
if [ -n "$LAST_REVIEW_TS" ] && [ "$TOTAL_NEW" -ge "$TIME_EVENT_MIN" ]; then
  # macOS-compatible date arithmetic with Linux fallback
  DAYS_SINCE=0
  NOW_EPOCH="$(date +%s)"

  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_REVIEW_TS" +%s >/dev/null 2>&1; then
    # macOS
    LAST_EPOCH="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_REVIEW_TS" +%s 2>/dev/null || echo 0)"
  elif date -d "$LAST_REVIEW_TS" +%s >/dev/null 2>&1; then
    # Linux / GNU date
    LAST_EPOCH="$(date -d "$LAST_REVIEW_TS" +%s 2>/dev/null || echo 0)"
  else
    LAST_EPOCH=0
  fi

  if [ "$LAST_EPOCH" -gt 0 ]; then
    SECONDS_SINCE=$(( NOW_EPOCH - LAST_EPOCH ))
    DAYS_SINCE=$(( SECONDS_SINCE / 86400 ))
  fi

  if [ "$DAYS_SINCE" -ge "$TIME_THRESHOLD_DAYS" ]; then
    echo "[Slipstream] $DAYS_SINCE days since last review, $TOTAL_NEW new friction events captured. Run /slipstream."
  fi
fi

exit 0
