#!/bin/bash
# slipstream-check-triggers.sh
# Fires on Stop and SessionStart. Checks per-module thresholds and prints specific
# commands to run when friction has accumulated enough to be worth reviewing.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"
CURSOR="$DATA_DIR/.cursor.json"

# Per-module thresholds
THRESHOLD_PERMISSIONS=5
THRESHOLD_COMPACTIONS=3
THRESHOLD_ERRORS=3
THRESHOLD_READS=10
THRESHOLD_CORRECTIONS=2

# Time-based threshold: if a module has any new data and last review was >7 days ago,
# include it regardless of count.
TIME_THRESHOLD_DAYS=7

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$DATA_DIR"

# ── Helper: count lines in a file ─────────────────────────────────────────────
count_lines() {
  local f="$1"
  if [ -f "$f" ]; then
    wc -l < "$f" | tr -d ' '
  else
    echo 0
  fi
}

# ── Helper: days since an ISO 8601 timestamp (macOS + Linux portable) ─────────
days_since() {
  local ts="$1"
  local now_epoch
  local last_epoch
  now_epoch="$(date +%s)"

  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s >/dev/null 2>&1; then
    # macOS BSD date
    last_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0)"
  elif date -d "$ts" +%s >/dev/null 2>&1; then
    # GNU date (Linux)
    last_epoch="$(date -d "$ts" +%s 2>/dev/null || echo 0)"
  else
    last_epoch=0
  fi

  if [ "$last_epoch" -gt 0 ]; then
    echo $(( (now_epoch - last_epoch) / 86400 ))
  else
    echo 9999
  fi
}

# ── Read cursor state ──────────────────────────────────────────────────────────
LAST_PERMISSIONS=0
LAST_COMPACTIONS=0
LAST_ERRORS=0
LAST_READS=0
LAST_PERMISSIONS_TS=""
LAST_CONTEXT_TS=""
LAST_ERRORS_TS=""
LAST_READS_TS=""
LAST_CORRECTIONS_TS=""

if [ -f "$CURSOR" ]; then
  LAST_PERMISSIONS="$(jq -r '.permissions_line_count // 0'    "$CURSOR")"
  LAST_COMPACTIONS="$(jq -r '.compactions_line_count // 0'    "$CURSOR")"
  LAST_ERRORS="$(jq -r      '.errors_line_count // 0'         "$CURSOR")"
  LAST_READS="$(jq -r       '.reads_line_count // 0'          "$CURSOR")"
  LAST_PERMISSIONS_TS="$(jq -r '.last_permissions_review // ""'  "$CURSOR")"
  LAST_CONTEXT_TS="$(jq -r    '.last_context_review // ""'       "$CURSOR")"
  LAST_ERRORS_TS="$(jq -r     '.last_errors_review // ""'        "$CURSOR")"
  LAST_READS_TS="$(jq -r      '.last_reads_review // ""'         "$CURSOR")"
  LAST_CORRECTIONS_TS="$(jq -r '.last_corrections_review // ""'  "$CURSOR")"
fi

# ── Current line counts ────────────────────────────────────────────────────────
CUR_PERMISSIONS="$(count_lines "$DATA_DIR/permissions.jsonl")"
CUR_COMPACTIONS="$(count_lines "$DATA_DIR/compactions.jsonl")"
CUR_ERRORS="$(count_lines      "$DATA_DIR/errors.jsonl")"
CUR_READS="$(count_lines       "$DATA_DIR/reads.jsonl")"

NEW_PERMISSIONS=$(( CUR_PERMISSIONS - LAST_PERMISSIONS ))
NEW_COMPACTIONS=$(( CUR_COMPACTIONS - LAST_COMPACTIONS ))
NEW_ERRORS=$(( CUR_ERRORS - LAST_ERRORS ))
NEW_READS=$(( CUR_READS - LAST_READS ))

# Guard against negatives (e.g. log rotation)
[ "$NEW_PERMISSIONS" -lt 0 ] && NEW_PERMISSIONS=0
[ "$NEW_COMPACTIONS" -lt 0 ] && NEW_COMPACTIONS=0
[ "$NEW_ERRORS" -lt 0 ]      && NEW_ERRORS=0
[ "$NEW_READS" -lt 0 ]       && NEW_READS=0

# ── Unanalyzed correction sessions ────────────────────────────────────────────
CORRECTIONS_STATE="$DATA_DIR/corrections-state.json"
ANALYZED_COUNT=0
if [ -f "$CORRECTIONS_STATE" ]; then
  ANALYZED_COUNT="$(jq -r '.analyzed_session_ids | length' "$CORRECTIONS_STATE" 2>/dev/null || echo 0)"
fi

TOTAL_SESSIONS=0
if [ -d "$HOME/.claude/projects" ]; then
  TOTAL_SESSIONS="$(find "$HOME/.claude/projects" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
fi

UNANALYZED=$(( TOTAL_SESSIONS - ANALYZED_COUNT ))
[ "$UNANALYZED" -lt 0 ] && UNANALYZED=0

# ── Build recommendation list ──────────────────────────────────────────────────
RECOMMENDATIONS=()

# Permissions
INCLUDE_PERMISSIONS=false
if [ "$NEW_PERMISSIONS" -ge "$THRESHOLD_PERMISSIONS" ]; then
  INCLUDE_PERMISSIONS=true
elif [ "$NEW_PERMISSIONS" -gt 0 ] && [ -n "$LAST_PERMISSIONS_TS" ]; then
  DAYS="$(days_since "$LAST_PERMISSIONS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_PERMISSIONS=true
fi
$INCLUDE_PERMISSIONS && RECOMMENDATIONS+=("/slipstream-permissions   ${NEW_PERMISSIONS} new events")

# Context (compactions)
INCLUDE_CONTEXT=false
if [ "$NEW_COMPACTIONS" -ge "$THRESHOLD_COMPACTIONS" ]; then
  INCLUDE_CONTEXT=true
elif [ "$NEW_COMPACTIONS" -gt 0 ] && [ -n "$LAST_CONTEXT_TS" ]; then
  DAYS="$(days_since "$LAST_CONTEXT_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_CONTEXT=true
fi
$INCLUDE_CONTEXT && RECOMMENDATIONS+=("/slipstream-context        ${NEW_COMPACTIONS} new events")

# Errors
INCLUDE_ERRORS=false
if [ "$NEW_ERRORS" -ge "$THRESHOLD_ERRORS" ]; then
  INCLUDE_ERRORS=true
elif [ "$NEW_ERRORS" -gt 0 ] && [ -n "$LAST_ERRORS_TS" ]; then
  DAYS="$(days_since "$LAST_ERRORS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_ERRORS=true
fi
$INCLUDE_ERRORS && RECOMMENDATIONS+=("/slipstream-errors          ${NEW_ERRORS} new events")

# Reads
INCLUDE_READS=false
if [ "$NEW_READS" -ge "$THRESHOLD_READS" ]; then
  INCLUDE_READS=true
elif [ "$NEW_READS" -gt 0 ] && [ -n "$LAST_READS_TS" ]; then
  DAYS="$(days_since "$LAST_READS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_READS=true
fi
$INCLUDE_READS && RECOMMENDATIONS+=("/slipstream-reads           ${NEW_READS} new events")

# Corrections
INCLUDE_CORRECTIONS=false
if [ "$UNANALYZED" -ge "$THRESHOLD_CORRECTIONS" ]; then
  INCLUDE_CORRECTIONS=true
elif [ "$UNANALYZED" -gt 0 ] && [ -n "$LAST_CORRECTIONS_TS" ]; then
  DAYS="$(days_since "$LAST_CORRECTIONS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_CORRECTIONS=true
fi
$INCLUDE_CORRECTIONS && RECOMMENDATIONS+=("/slipstream-corrections    ${UNANALYZED} unanalyzed sessions")

# ── Print output ───────────────────────────────────────────────────────────────
if [ "${#RECOMMENDATIONS[@]}" -gt 0 ]; then
  echo "[Slipstream]"
  for rec in "${RECOMMENDATIONS[@]}"; do
    echo "  $rec"
  done
fi

exit 0
