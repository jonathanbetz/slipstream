#!/bin/bash
# SessionStart hook — fires at the beginning of every Claude Code session.
#
# 1. Checks whether any module already exceeds its threshold FOR THE CURRENT
#    PROJECT and prints an immediate alert if so.
# 2. Always instructs Claude to set up an hourly in-session CronCreate job
#    that silently re-checks thresholds and runs the appropriate command if
#    data has accumulated. If no threshold is met the cron does nothing.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"

# Per-module thresholds — single source of truth
# shellcheck source=slipstream-thresholds.sh
. "$(dirname "$0")/slipstream-thresholds.sh"

# Never block Claude Code
trap 'exit 0' ERR

# ── Determine current project from hook stdin ──────────────────────────────
INPUT="$(cat)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")"
[ -z "$CWD" ] && CWD="$(pwd)"

# Encode project path the same way Claude Code does:
# /Users/alice/src/myapp → -Users-alice-src-myapp
PROJECT_KEY="$(printf '%s' "$CWD" | sed 's|/|-|g')"

CURSOR_FILE="$DATA_DIR/cursors/${PROJECT_KEY}.json"
PROJECT_SESSIONS_DIR="$HOME/.claude/projects/${PROJECT_KEY}"

mkdir -p "$DATA_DIR/cursors"

# ── Helper: count events for current project since a timestamp ────────────────
count_new() {
  local file="$DATA_DIR/$1"
  local key="$2"
  local last_ts
  last_ts="$(jq -r ".$key // \"1970-01-01T00:00:00Z\"" "$CURSOR_FILE" 2>/dev/null || echo "1970-01-01T00:00:00Z")"
  if [ ! -f "$file" ]; then
    echo 0
    return
  fi
  jq -c \
    --arg cwd "$CWD" \
    --arg ts "$last_ts" \
    'select((.cwd | startswith($cwd)) and .timestamp > $ts)' \
    "$file" 2>/dev/null | wc -l | tr -d ' '
}

PERM_NEW=$(count_new "permissions.jsonl"  "last_permissions_review")
COMP_NEW=$(count_new "compactions.jsonl"  "last_context_review")
ERR_NEW=$(count_new  "errors.jsonl"       "last_errors_review")
READ_NEW=$(count_new "reads.jsonl"        "last_reads_review")

# ── Unanalyzed sessions for current project ────────────────────────────────────
TOTAL_SESSIONS=0
if [ -d "$PROJECT_SESSIONS_DIR" ]; then
  TOTAL_SESSIONS=$(find "$PROJECT_SESSIONS_DIR" -maxdepth 1 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
fi

# Helper: count analyzed sessions that belong to this project
count_project_analyzed() {
  local state_file="$1"
  if [ ! -f "$state_file" ] || [ ! -d "$PROJECT_SESSIONS_DIR" ]; then
    echo 0
    return
  fi
  find "$PROJECT_SESSIONS_DIR" -maxdepth 1 -name '*.jsonl' 2>/dev/null \
    | xargs -I{} basename {} .jsonl \
    | jq -R . | jq -s \
      --slurpfile state "$state_file" \
      '[.[] | select(. as $id | $state[0].analyzed_session_ids | index($id) != null)] | length' \
      2>/dev/null || echo 0
}

CORR_ANALYZED=$(count_project_analyzed "$DATA_DIR/corrections-state.json")
CORR_NEW=$(( TOTAL_SESSIONS - CORR_ANALYZED ))
[ "$CORR_NEW" -lt 0 ] && CORR_NEW=0

MEM_ANALYZED=$(count_project_analyzed "$DATA_DIR/memory-state.json")
MEM_NEW=$(( TOTAL_SESSIONS - MEM_ANALYZED ))
[ "$MEM_NEW" -lt 0 ] && MEM_NEW=0

CMD_ANALYZED=$(count_project_analyzed "$DATA_DIR/commands-state.json")
CMD_NEW=$(( TOTAL_SESSIONS - CMD_ANALYZED ))
[ "$CMD_NEW" -lt 0 ] && CMD_NEW=0

# ── Build immediate alert (if anything already over threshold) ─────────────────
ALERTS=""
[ "$PERM_NEW" -ge "$THRESHOLD_PERMISSIONS"  ] && ALERTS="${ALERTS}  /slipstream-permissions   ${PERM_NEW} new events\n"
[ "$COMP_NEW" -ge "$THRESHOLD_COMPACTIONS"  ] && ALERTS="${ALERTS}  /slipstream-context       ${COMP_NEW} new compactions\n"
[ "$ERR_NEW"  -ge "$THRESHOLD_ERRORS"       ] && ALERTS="${ALERTS}  /slipstream-errors        ${ERR_NEW} new failures\n"
[ "$READ_NEW" -ge "$THRESHOLD_READS"        ] && ALERTS="${ALERTS}  /slipstream-reads         ${READ_NEW} new reads\n"
[ "$CORR_NEW" -ge "$THRESHOLD_CORRECTIONS"  ] && ALERTS="${ALERTS}  /slipstream-corrections   ${CORR_NEW} unanalyzed sessions\n"
[ "$MEM_NEW"  -ge "$THRESHOLD_MEMORY"       ] && ALERTS="${ALERTS}  /slipstream-memory        ${MEM_NEW} unanalyzed sessions\n"
[ "$CMD_NEW"  -ge "$THRESHOLD_COMMANDS"     ] && ALERTS="${ALERTS}  /slipstream-commands      ${CMD_NEW} unanalyzed sessions\n"

if [ -n "$ALERTS" ]; then
  printf "[Slipstream] Friction ready for review:\n%b" "$ALERTS"
fi

# Always set up the hourly in-session cron.
# Embed CWD and PROJECT_KEY so the cron filters to the same project.
cat <<CRON_INSTRUCTION
[Slipstream] Please call the CronCreate tool now to set up an hourly friction monitor for this session:
  cron: "7 * * * *"
  recurring: true
  prompt: "Slipstream hourly check for project ${CWD} — run silently, only surface recommendations if a threshold is exceeded, and always wait for user approval before changing anything. The current project path is: ${CWD}. The project key (path with / replaced by -) is: ${PROJECT_KEY}. Read the per-project cursor from ~/.slipstream/cursors/${PROJECT_KEY}.json (default {}). Count new events since last review timestamps in that cursor, filtered to entries where .cwd starts with '${CWD}': permissions=$(jq -r --arg cwd '${CWD}' --arg ts \$(jq -r '.last_permissions_review // \"1970-01-01T00:00:00Z\"' ~/.slipstream/cursors/${PROJECT_KEY}.json 2>/dev/null || echo 1970-01-01T00:00:00Z) 'select((.cwd|startswith(\$cwd)) and .timestamp>\$ts)' ~/.slipstream/permissions.jsonl 2>/dev/null | wc -l | tr -d ' '), compactions similarly, errors similarly, reads similarly. Count unanalyzed sessions by looking only at *.jsonl files under ~/.claude/projects/${PROJECT_KEY}/ and subtracting analyzed_session_ids in each state file. Then: if permissions new>=${THRESHOLD_PERMISSIONS} run /slipstream-permissions; if compactions new>=${THRESHOLD_COMPACTIONS} run /slipstream-context; if errors new>=${THRESHOLD_ERRORS} run /slipstream-errors; if reads new>=${THRESHOLD_READS} run /slipstream-reads; if corrections unanalyzed>=${THRESHOLD_CORRECTIONS} run /slipstream-corrections; if memory unanalyzed>=${THRESHOLD_MEMORY} run /slipstream-memory; if commands unanalyzed>=${THRESHOLD_COMMANDS} run /slipstream-commands. Each command will present a plan and wait for your approval — nothing is applied automatically. If no threshold is exceeded, say nothing and do nothing."
CRON_INSTRUCTION

exit 0
