#!/bin/bash
# SessionStart hook — fires at the beginning of every Claude Code session.
#
# 1. Checks whether any module already exceeds its threshold and prints an
#    immediate alert if so.
# 2. Always instructs Claude to set up an hourly in-session CronCreate job
#    that silently re-checks thresholds and runs the appropriate command if
#    data has accumulated. If no threshold is met the cron does nothing.

DATA_DIR="$HOME/.slipstream"
CURSOR_FILE="$DATA_DIR/.cursor.json"

count_new() {
  local file="$DATA_DIR/$1"
  local key="$2"
  local current=0
  local last=0
  [ -f "$file" ] && current=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  last=$(jq -r ".$key // 0" "$CURSOR_FILE" 2>/dev/null || echo 0)
  echo $(( current - last ))
}

PERM_NEW=$(count_new "permissions.jsonl"  "permissions_line_count")
COMP_NEW=$(count_new "compactions.jsonl"  "compactions_line_count")
ERR_NEW=$(count_new  "errors.jsonl"       "errors_line_count")
READ_NEW=$(count_new "reads.jsonl"        "reads_line_count")

# Unanalyzed correction sessions
TOTAL_SESSIONS=0
ANALYZED=0
if [ -d "$HOME/.claude/projects" ]; then
  TOTAL_SESSIONS=$(find "$HOME/.claude/projects" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
fi
ANALYZED=$(jq -r '.analyzed_session_ids | length' "$DATA_DIR/corrections-state.json" 2>/dev/null || echo 0)
CORR_NEW=$(( TOTAL_SESSIONS - ANALYZED ))
[ "$CORR_NEW" -lt 0 ] && CORR_NEW=0

# Memory: unanalyzed sessions
MEM_ANALYZED=$(jq -r '.analyzed_session_ids | length' "$DATA_DIR/memory-state.json" 2>/dev/null || echo 0)
MEM_NEW=$(( TOTAL_SESSIONS - MEM_ANALYZED ))
[ "$MEM_NEW" -lt 0 ] && MEM_NEW=0

# Commands: unanalyzed sessions
CMD_ANALYZED=$(jq -r '.analyzed_session_ids | length' "$DATA_DIR/commands-state.json" 2>/dev/null || echo 0)
CMD_NEW=$(( TOTAL_SESSIONS - CMD_ANALYZED ))
[ "$CMD_NEW" -lt 0 ] && CMD_NEW=0

# Build immediate alert (if anything already over threshold)
ALERTS=""
[ "$PERM_NEW" -ge 5  ] && ALERTS="${ALERTS}  /slipstream-permissions   ${PERM_NEW} new events\n"
[ "$COMP_NEW" -ge 3  ] && ALERTS="${ALERTS}  /slipstream-context       ${COMP_NEW} new compactions\n"
[ "$ERR_NEW"  -ge 3  ] && ALERTS="${ALERTS}  /slipstream-errors        ${ERR_NEW} new failures\n"
[ "$READ_NEW" -ge 10 ] && ALERTS="${ALERTS}  /slipstream-reads         ${READ_NEW} new reads\n"
[ "$CORR_NEW" -ge 2  ] && ALERTS="${ALERTS}  /slipstream-corrections   ${CORR_NEW} unanalyzed sessions\n"
[ "$MEM_NEW"  -ge 2  ] && ALERTS="${ALERTS}  /slipstream-memory        ${MEM_NEW} unanalyzed sessions\n"
[ "$CMD_NEW"  -ge 3  ] && ALERTS="${ALERTS}  /slipstream-commands      ${CMD_NEW} unanalyzed sessions\n"

if [ -n "$ALERTS" ]; then
  printf "[Slipstream] Friction ready for review:\n%b" "$ALERTS"
fi

# Always set up the hourly in-session cron.
# The cron prompt is intentionally terse — it runs silently unless action is needed.
cat <<'CRON_INSTRUCTION'
[Slipstream] Please call the CronCreate tool now to set up an hourly friction monitor for this session:
  cron: "7 * * * *"
  recurring: true
  prompt: "Slipstream hourly check — run silently, only surface recommendations if a threshold is exceeded, and always wait for user approval before changing anything. Read line counts: permissions=$(wc -l < ~/.slipstream/permissions.jsonl 2>/dev/null || echo 0), compactions=$(wc -l < ~/.slipstream/compactions.jsonl 2>/dev/null || echo 0), errors=$(wc -l < ~/.slipstream/errors.jsonl 2>/dev/null || echo 0), reads=$(wc -l < ~/.slipstream/reads.jsonl 2>/dev/null || echo 0). Read baselines from ~/.slipstream/.cursor.json. Compute new = current - baseline for each. Count total *.jsonl files under ~/.claude/projects/. Count unanalyzed sessions for each transcript module: corrections unanalyzed = total minus analyzed_session_ids in ~/.slipstream/corrections-state.json; memory unanalyzed = total minus analyzed_session_ids in ~/.slipstream/memory-state.json; commands unanalyzed = total minus analyzed_session_ids in ~/.slipstream/commands-state.json. Then: if permissions new>=5 run /slipstream-permissions; if compactions new>=3 run /slipstream-context; if errors new>=3 run /slipstream-errors; if reads new>=10 run /slipstream-reads; if corrections unanalyzed>=2 run /slipstream-corrections; if memory unanalyzed>=2 run /slipstream-memory; if commands unanalyzed>=3 run /slipstream-commands. Each command will present a plan and wait for your approval — nothing is applied automatically. If no threshold is exceeded, say nothing and do nothing."
CRON_INSTRUCTION

exit 0
