#!/usr/bin/env bats
# Slipstream test suite
# Run with: bats tests/slipstream.bats
#
# Requires: bats-core >= 1.7
#   macOS:  brew install bats-core
#   Ubuntu: sudo apt-get install bats

REPO_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
HOOKS_DIR="$REPO_DIR/hooks"
FIXTURES_DIR="$REPO_DIR/tests/fixtures"

# Each test gets an isolated home dir so we never touch the real ~/.slipstream
setup() {
  FAKE_HOME="$(mktemp -d)"
  export HOME="$FAKE_HOME"
  export SLIPSTREAM_DATA_DIR="$FAKE_HOME/.slipstream"
  mkdir -p "$FAKE_HOME/.slipstream"
  mkdir -p "$FAKE_HOME/.claude/projects"

  # Make all hook scripts executable for tests
  chmod +x "$HOOKS_DIR"/slipstream-*.sh 2>/dev/null || true
}

teardown() {
  rm -rf "$FAKE_HOME"
}

# ── Helper ────────────────────────────────────────────────────────────────────

# Run a capture script with fixture input, return its exit code
run_capture() {
  local script="$1"
  local fixture="$2"
  run bash "$HOOKS_DIR/$script" < "$FIXTURES_DIR/$fixture"
}

# ── Group 1: Capture scripts produce valid JSON and exit 0 ────────────────────

@test "capture-permission: exits 0 on valid input" {
  run_capture slipstream-capture-permission.sh valid-permission.json
  [ "$status" -eq 0 ]
}

@test "capture-permission: writes exactly one valid JSON line" {
  bash "$HOOKS_DIR/slipstream-capture-permission.sh" \
    < "$FIXTURES_DIR/valid-permission.json"
  local log="$FAKE_HOME/.slipstream/permissions.jsonl"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
  jq -e . "$log" >/dev/null
}

@test "capture-permission: written line has required fields" {
  bash "$HOOKS_DIR/slipstream-capture-permission.sh" \
    < "$FIXTURES_DIR/valid-permission.json"
  local log="$FAKE_HOME/.slipstream/permissions.jsonl"
  local line
  line="$(cat "$log")"
  echo "$line" | jq -e '.timestamp' >/dev/null
  echo "$line" | jq -e '.session_id' >/dev/null
  echo "$line" | jq -e '.cwd' >/dev/null
  echo "$line" | jq -e '.tool_name' >/dev/null
  echo "$line" | jq -e '.tool_input' >/dev/null
}

@test "capture-compaction: exits 0 and writes valid JSON" {
  bash "$HOOKS_DIR/slipstream-capture-compaction.sh" \
    < "$FIXTURES_DIR/valid-compaction.json"
  local log="$FAKE_HOME/.slipstream/compactions.jsonl"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
  jq -e . "$log" >/dev/null
}

@test "capture-errors: exits 0 and writes valid JSON" {
  bash "$HOOKS_DIR/slipstream-capture-errors.sh" \
    < "$FIXTURES_DIR/valid-error.json"
  local log="$FAKE_HOME/.slipstream/errors.jsonl"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
  jq -e . "$log" >/dev/null
}

@test "capture-reads: logs Read tool use" {
  bash "$HOOKS_DIR/slipstream-capture-reads.sh" \
    < "$FIXTURES_DIR/valid-reads-read.json"
  local log="$FAKE_HOME/.slipstream/reads.jsonl"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
  jq -e '.file_path' "$log" >/dev/null
}

@test "capture-reads: logs Glob tool use" {
  bash "$HOOKS_DIR/slipstream-capture-reads.sh" \
    < "$FIXTURES_DIR/valid-reads-glob.json"
  local log="$FAKE_HOME/.slipstream/reads.jsonl"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
  jq -e '.file_path' "$log" >/dev/null
}

@test "capture-reads: skips non-Read/Glob tool uses" {
  # Bash tool event — should not be logged
  echo '{"session_id":"s1","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | bash "$HOOKS_DIR/slipstream-capture-reads.sh"
  local log="$FAKE_HOME/.slipstream/reads.jsonl"
  [ ! -f "$log" ]
}

# ── Group 2: Malformed JSON handling ─────────────────────────────────────────

@test "capture-permission: exits 0 on malformed JSON (never blocks Claude)" {
  run_capture slipstream-capture-permission.sh malformed.json
  [ "$status" -eq 0 ]
}

@test "capture-permission: writes to errors.log on malformed JSON" {
  bash "$HOOKS_DIR/slipstream-capture-permission.sh" \
    < "$FIXTURES_DIR/malformed.json" || true
  local errlog="$FAKE_HOME/.slipstream/errors.log"
  [ -f "$errlog" ]
  grep -q "slipstream-capture-permission" "$errlog"
}

@test "capture-permission: does NOT append to permissions.jsonl on malformed JSON" {
  bash "$HOOKS_DIR/slipstream-capture-permission.sh" \
    < "$FIXTURES_DIR/malformed.json" || true
  local log="$FAKE_HOME/.slipstream/permissions.jsonl"
  [ ! -f "$log" ] || [ "$(wc -l < "$log" | tr -d ' ')" -eq 0 ]
}

@test "capture-compaction: exits 0 on malformed JSON" {
  run_capture slipstream-capture-compaction.sh malformed.json
  [ "$status" -eq 0 ]
}

@test "capture-errors: exits 0 on malformed JSON" {
  run_capture slipstream-capture-errors.sh malformed.json
  [ "$status" -eq 0 ]
}

@test "capture-reads: exits 0 on malformed JSON" {
  run_capture slipstream-capture-reads.sh malformed.json
  [ "$status" -eq 0 ]
}

# ── Group 3: Empty / missing .cursor.json ─────────────────────────────────────

@test "check-triggers: exits 0 when .cursor.json is missing" {
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [ "$status" -eq 0 ]
}

@test "check-triggers: exits 0 with empty .cursor.json" {
  echo '{}' > "$FAKE_HOME/.slipstream/.cursor.json"
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [ "$status" -eq 0 ]
}

@test "check-triggers: produces no output when no data accumulated" {
  echo '{}' > "$FAKE_HOME/.slipstream/.cursor.json"
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [ -z "$output" ]
}

# ── Group 4: Negative new-event counts (log rotation / deletion scenario) ─────

@test "check-triggers: handles negative new counts without error" {
  # Cursor says we had 100 permissions, but file only has 5 lines → new = -95
  printf '%s\n' '{"permissions_line_count": 100}' \
    > "$FAKE_HOME/.slipstream/.cursor.json"
  for i in $(seq 1 5); do
    printf '{"timestamp":"2026-01-01T00:00:00Z","session_id":"s%d","cwd":"/tmp","tool_name":"Bash","tool_input":{}}\n' "$i" \
      >> "$FAKE_HOME/.slipstream/permissions.jsonl"
  done
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [ "$status" -eq 0 ]
  # Should NOT recommend /slipstream-permissions (negative new treated as 0)
  [[ "$output" != *"/slipstream-permissions"* ]]
}

# ── Group 5: Trigger thresholds ───────────────────────────────────────────────

# Source thresholds to get the real values
load_thresholds() {
  # shellcheck source=/dev/null
  . "$HOOKS_DIR/slipstream-thresholds.sh"
}

# Generate N valid permission log lines
make_permission_lines() {
  local n="$1"
  local log="$FAKE_HOME/.slipstream/permissions.jsonl"
  for i in $(seq 1 "$n"); do
    printf '{"timestamp":"2026-01-01T00:00:0%dZ","session_id":"s%d","cwd":"/tmp","tool_name":"Bash","tool_input":{}}\n' \
      "$((i % 10))" "$i" >> "$log"
  done
}

@test "check-triggers: does NOT recommend permissions when below threshold" {
  load_thresholds
  make_permission_lines $(( THRESHOLD_PERMISSIONS - 1 ))
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [[ "$output" != *"/slipstream-permissions"* ]]
}

@test "check-triggers: recommends permissions when at threshold" {
  load_thresholds
  make_permission_lines "$THRESHOLD_PERMISSIONS"
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [[ "$output" == *"/slipstream-permissions"* ]]
}

@test "check-triggers: recommends permissions when above threshold" {
  load_thresholds
  make_permission_lines $(( THRESHOLD_PERMISSIONS + 3 ))
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [[ "$output" == *"/slipstream-permissions"* ]]
}

@test "check-triggers: does NOT recommend errors when below threshold" {
  load_thresholds
  local log="$FAKE_HOME/.slipstream/errors.jsonl"
  for i in $(seq 1 $(( THRESHOLD_ERRORS - 1 )) ); do
    printf '{"timestamp":"2026-01-01T00:00:00Z","session_id":"s%d","cwd":"/tmp","tool_name":"Bash","tool_input":{}}\n' "$i" \
      >> "$log"
  done
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [[ "$output" != *"/slipstream-errors"* ]]
}

@test "check-triggers: recommends errors when at threshold" {
  load_thresholds
  local log="$FAKE_HOME/.slipstream/errors.jsonl"
  for i in $(seq 1 "$THRESHOLD_ERRORS"); do
    printf '{"timestamp":"2026-01-01T00:00:00Z","session_id":"s%d","cwd":"/tmp","tool_name":"Bash","tool_input":{}}\n' "$i" \
      >> "$log"
  done
  run bash "$HOOKS_DIR/slipstream-check-triggers.sh"
  [[ "$output" == *"/slipstream-errors"* ]]
}

# ── Group 6: thresholds file is the single source of truth ───────────────────

@test "slipstream-thresholds.sh: defines all required variables" {
  load_thresholds
  [ -n "$THRESHOLD_PERMISSIONS" ]
  [ -n "$THRESHOLD_COMPACTIONS" ]
  [ -n "$THRESHOLD_ERRORS" ]
  [ -n "$THRESHOLD_READS" ]
  [ -n "$THRESHOLD_CORRECTIONS" ]
  [ -n "$THRESHOLD_MEMORY" ]
  [ -n "$THRESHOLD_COMMANDS" ]
  [ -n "$TIME_THRESHOLD_DAYS" ]
}

@test "session-start.sh cron prompt contains threshold values from thresholds file" {
  load_thresholds
  output="$(bash "$HOOKS_DIR/slipstream-session-start.sh" 2>/dev/null || true)"
  # The cron prompt must embed the actual threshold values, not hardcoded literals
  [[ "$output" == *">=${THRESHOLD_PERMISSIONS}"* ]]
  [[ "$output" == *">=${THRESHOLD_ERRORS}"* ]]
}

# ── Group 7: Concurrent writes (flock) ────────────────────────────────────────

@test "capture-permission: concurrent writes produce correct line count" {
  local log="$FAKE_HOME/.slipstream/permissions.jsonl"
  local n=10
  for i in $(seq 1 "$n"); do
    bash "$HOOKS_DIR/slipstream-capture-permission.sh" \
      < "$FIXTURES_DIR/valid-permission.json" &
  done
  wait
  local lines
  lines="$(wc -l < "$log" | tr -d ' ')"
  [ "$lines" -eq "$n" ]
  # All lines must be valid JSON
  while IFS= read -r line; do
    echo "$line" | jq -e . >/dev/null
  done < "$log"
}

# ── Group 8: install.sh creates backups directory ─────────────────────────────

@test "install.sh creates ~/.slipstream/backups directory" {
  # Minimal smoke test — check that the mkdir line includes /backups
  grep -q 'DATA_DIR/backups\|\.slipstream/backups' "$REPO_DIR/install.sh"
}
