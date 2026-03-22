#!/bin/bash
# slipstream-check-triggers.sh
# Fires on Stop and SessionStart. Checks per-module thresholds for the CURRENT
# PROJECT only and prints specific commands to run when friction has accumulated
# enough to be worth reviewing.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"

# Per-module thresholds — single source of truth
# shellcheck source=slipstream-thresholds.sh
. "$(dirname "$0")/slipstream-thresholds.sh"

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$DATA_DIR/projects"

# ── Determine current project from hook stdin ──────────────────────────────
INPUT="$(cat)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")"

# If no cwd in event, fall back to process working directory
[ -z "$CWD" ] && CWD="$(pwd)"

# Encode project path the same way Claude Code does:
# /Users/alice/src/myapp → -Users-alice-src-myapp
PROJECT_KEY="$(printf '%s' "$CWD" | sed 's|/|-|g')"

# Per-project cursor and session directory
CURSOR="$DATA_DIR/cursors/${PROJECT_KEY}.json"
PROJECT_DIR="$DATA_DIR/projects/${PROJECT_KEY}"
PROJECT_SESSIONS_DIR="$HOME/.claude/projects/${PROJECT_KEY}"

mkdir -p "$DATA_DIR/cursors" "$PROJECT_DIR"

# ── Helper: days since an ISO 8601 timestamp (macOS + Linux portable) ─────────
days_since() {
  local ts="$1"
  local now_epoch
  local last_epoch
  now_epoch="$(date +%s)"

  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s >/dev/null 2>&1; then
    last_epoch="$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0)"
  elif date -d "$ts" +%s >/dev/null 2>&1; then
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

# ── Helper: count events since a timestamp ────────────────────────────────────
# Usage: count_new <jsonl_file> <last_review_ts>
count_new() {
  local file="$1"
  local last_ts="${2:-1970-01-01T00:00:00Z}"
  if [ ! -f "$file" ]; then
    echo 0
    return
  fi
  jq -c --arg ts "$last_ts" 'select(.timestamp > $ts)' \
    "$file" 2>/dev/null | wc -l | tr -d ' '
}

# ── Read per-project cursor ────────────────────────────────────────────────────
LAST_PERMISSIONS_TS=""
LAST_CONTEXT_TS=""
LAST_ERRORS_TS=""
LAST_READS_TS=""
LAST_CORRECTIONS_TS=""
LAST_MEMORY_TS=""
LAST_COMMANDS_TS=""

if [ -f "$CURSOR" ]; then
  LAST_PERMISSIONS_TS="$(jq -r '.last_permissions_review // ""'  "$CURSOR")"
  LAST_CONTEXT_TS="$(jq -r    '.last_context_review // ""'       "$CURSOR")"
  LAST_ERRORS_TS="$(jq -r     '.last_errors_review // ""'        "$CURSOR")"
  LAST_READS_TS="$(jq -r      '.last_reads_review // ""'         "$CURSOR")"
  LAST_CORRECTIONS_TS="$(jq -r '.last_corrections_review // ""'  "$CURSOR")"
  LAST_MEMORY_TS="$(jq -r   '.last_memory_review // ""'          "$CURSOR")"
  LAST_COMMANDS_TS="$(jq -r '.last_commands_review // ""'        "$CURSOR")"
fi

# ── New events since last review ──────────────────────────────────────────────
NEW_PERMISSIONS="$(count_new "$PROJECT_DIR/permissions.jsonl" "$LAST_PERMISSIONS_TS")"
NEW_COMPACTIONS="$(count_new "$PROJECT_DIR/compactions.jsonl" "$LAST_CONTEXT_TS")"
NEW_ERRORS="$(count_new      "$PROJECT_DIR/errors.jsonl"      "$LAST_ERRORS_TS")"
NEW_READS="$(count_new       "$PROJECT_DIR/reads.jsonl"        "$LAST_READS_TS")"

# ── Unanalyzed sessions for current project ────────────────────────────────────
TOTAL_SESSIONS=0
if [ -d "$PROJECT_SESSIONS_DIR" ]; then
  TOTAL_SESSIONS="$(find "$PROJECT_SESSIONS_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
fi

# Corrections
CORRECTIONS_STATE="$DATA_DIR/corrections-state.json"
ANALYZED_COUNT=0
if [ -f "$CORRECTIONS_STATE" ]; then
  # Count how many of this project's sessions are already analyzed
  if [ -d "$PROJECT_SESSIONS_DIR" ]; then
    ANALYZED_COUNT="$(find "$PROJECT_SESSIONS_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null \
      | xargs -I{} basename {} .jsonl \
      | jq -R . | jq -s \
        --slurpfile state "$CORRECTIONS_STATE" \
        '[.[] | select(. as $id | $state[0].analyzed_session_ids | index($id) != null)] | length' \
        2>/dev/null || echo 0)"
  fi
fi
UNANALYZED=$(( TOTAL_SESSIONS - ANALYZED_COUNT ))
[ "$UNANALYZED" -lt 0 ] && UNANALYZED=0

# Memory
MEMORY_STATE="$DATA_DIR/memory-state.json"
MEM_ANALYZED_COUNT=0
if [ -f "$MEMORY_STATE" ] && [ -d "$PROJECT_SESSIONS_DIR" ]; then
  MEM_ANALYZED_COUNT="$(find "$PROJECT_SESSIONS_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null \
    | xargs -I{} basename {} .jsonl \
    | jq -R . | jq -s \
      --slurpfile state "$MEMORY_STATE" \
      '[.[] | select(. as $id | $state[0].analyzed_session_ids | index($id) != null)] | length' \
      2>/dev/null || echo 0)"
fi
MEM_UNANALYZED=$(( TOTAL_SESSIONS - MEM_ANALYZED_COUNT ))
[ "$MEM_UNANALYZED" -lt 0 ] && MEM_UNANALYZED=0

# Commands
COMMANDS_STATE="$DATA_DIR/commands-state.json"
CMD_ANALYZED_COUNT=0
if [ -f "$COMMANDS_STATE" ] && [ -d "$PROJECT_SESSIONS_DIR" ]; then
  CMD_ANALYZED_COUNT="$(find "$PROJECT_SESSIONS_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null \
    | xargs -I{} basename {} .jsonl \
    | jq -R . | jq -s \
      --slurpfile state "$COMMANDS_STATE" \
      '[.[] | select(. as $id | $state[0].analyzed_session_ids | index($id) != null)] | length' \
      2>/dev/null || echo 0)"
fi
CMD_UNANALYZED=$(( TOTAL_SESSIONS - CMD_ANALYZED_COUNT ))
[ "$CMD_UNANALYZED" -lt 0 ] && CMD_UNANALYZED=0

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
$INCLUDE_PERMISSIONS && RECOMMENDATIONS+=("/slipstream-permissions (${NEW_PERMISSIONS} allow-list candidates)")

# Context (compactions)
INCLUDE_CONTEXT=false
if [ "$NEW_COMPACTIONS" -ge "$THRESHOLD_COMPACTIONS" ]; then
  INCLUDE_CONTEXT=true
elif [ "$NEW_COMPACTIONS" -gt 0 ] && [ -n "$LAST_CONTEXT_TS" ]; then
  DAYS="$(days_since "$LAST_CONTEXT_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_CONTEXT=true
fi
$INCLUDE_CONTEXT && RECOMMENDATIONS+=("/slipstream-context (${NEW_COMPACTIONS} compactions)")

# Errors
INCLUDE_ERRORS=false
if [ "$NEW_ERRORS" -ge "$THRESHOLD_ERRORS" ]; then
  INCLUDE_ERRORS=true
elif [ "$NEW_ERRORS" -gt 0 ] && [ -n "$LAST_ERRORS_TS" ]; then
  DAYS="$(days_since "$LAST_ERRORS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_ERRORS=true
fi
$INCLUDE_ERRORS && RECOMMENDATIONS+=("/slipstream-errors (${NEW_ERRORS} tool failures)")

# Reads
INCLUDE_READS=false
if [ "$NEW_READS" -ge "$THRESHOLD_READS" ]; then
  INCLUDE_READS=true
elif [ "$NEW_READS" -gt 0 ] && [ -n "$LAST_READS_TS" ]; then
  DAYS="$(days_since "$LAST_READS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_READS=true
fi
$INCLUDE_READS && RECOMMENDATIONS+=("/slipstream-reads (${NEW_READS} orientation reads)")

# Corrections
INCLUDE_CORRECTIONS=false
if [ "$UNANALYZED" -ge "$THRESHOLD_CORRECTIONS" ]; then
  INCLUDE_CORRECTIONS=true
elif [ "$UNANALYZED" -gt 0 ] && [ -n "$LAST_CORRECTIONS_TS" ]; then
  DAYS="$(days_since "$LAST_CORRECTIONS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_CORRECTIONS=true
fi
$INCLUDE_CORRECTIONS && RECOMMENDATIONS+=("/slipstream-corrections (${UNANALYZED} sessions to mine)")

# Memory
INCLUDE_MEMORY=false
if [ "$MEM_UNANALYZED" -ge "$THRESHOLD_MEMORY" ]; then
  INCLUDE_MEMORY=true
elif [ "$MEM_UNANALYZED" -gt 0 ] && [ -n "$LAST_MEMORY_TS" ]; then
  DAYS="$(days_since "$LAST_MEMORY_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_MEMORY=true
fi
$INCLUDE_MEMORY && RECOMMENDATIONS+=("/slipstream-memory (${MEM_UNANALYZED} sessions to mine)")

# Commands
INCLUDE_COMMANDS=false
if [ "$CMD_UNANALYZED" -ge "$THRESHOLD_COMMANDS" ]; then
  INCLUDE_COMMANDS=true
elif [ "$CMD_UNANALYZED" -gt 0 ] && [ -n "$LAST_COMMANDS_TS" ]; then
  DAYS="$(days_since "$LAST_COMMANDS_TS")"
  [ "$DAYS" -ge "$TIME_THRESHOLD_DAYS" ] && INCLUDE_COMMANDS=true
fi
$INCLUDE_COMMANDS && RECOMMENDATIONS+=("/slipstream-commands (${CMD_UNANALYZED} sessions to mine)")

# ── Print one-line summary ─────────────────────────────────────────────────────
if [ "${#RECOMMENDATIONS[@]}" -gt 0 ]; then
  # Join recommendations with " · "
  LINE=""
  for rec in "${RECOMMENDATIONS[@]}"; do
    [ -n "$LINE" ] && LINE="${LINE} · "
    LINE="${LINE}${rec}"
  done
  printf '[Slipstream] Ready: %s\n' "$LINE"
fi

exit 0
