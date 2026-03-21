#!/bin/bash
# install.sh — Slipstream installer
# Copies hooks and commands into ~/.claude/ and merges hook entries into
# ~/.claude/settings.json idempotently.

set -e

echo ""
echo "┌─────────────────────────────────────────┐"
echo "│  Installing Slipstream...               │"
echo "└─────────────────────────────────────────┘"
echo ""

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found."
  echo ""
  echo "Install it with:"
  echo "  macOS:   brew install jq"
  echo "  Ubuntu:  sudo apt-get install jq"
  echo "  Fedora:  sudo dnf install jq"
  exit 1
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
COMMANDS_DIR="$CLAUDE_DIR/commands"
DATA_DIR="$HOME/.slipstream"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$HOOKS_DIR" "$COMMANDS_DIR" "$DATA_DIR"

# ── Copy hooks ────────────────────────────────────────────────────────────────
echo "Copying hook scripts to $HOOKS_DIR ..."
for hook in "$SCRIPT_DIR"/hooks/slipstream-*.sh; do
  dest="$HOOKS_DIR/$(basename "$hook")"
  cp "$hook" "$dest"
  chmod +x "$dest"
  echo "  ✓ $(basename "$hook")"
done

# ── Copy commands ─────────────────────────────────────────────────────────────
echo ""
echo "Copying commands to $COMMANDS_DIR ..."
for cmd in "$SCRIPT_DIR"/commands/slipstream*.md; do
  dest="$COMMANDS_DIR/$(basename "$cmd")"
  cp "$cmd" "$dest"
  echo "  ✓ $(basename "$cmd")"
done

# ── Bootstrap settings.json ───────────────────────────────────────────────────
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Ensure .hooks key exists
CURRENT="$(cat "$SETTINGS")"
if ! echo "$CURRENT" | jq -e '.hooks' >/dev/null 2>&1; then
  echo "$CURRENT" | jq '. + {"hooks": {}}' > "$SETTINGS"
fi

# ── merge_hook() ──────────────────────────────────────────────────────────────
# Usage:
#   merge_hook <event_name> <command_path>
#   merge_hook <event_name> <command_path> <matcher>
#
# Appends a hook entry to .hooks[<event_name>] only if the command_path is not
# already present. Handles both plain and matcher-based entries.
merge_hook() {
  local event="$1"
  local cmd_path="$2"
  local matcher="${3:-}"
  local settings_tmp

  settings_tmp="$(mktemp)"

  # Check whether this command is already registered for this event
  local already_present
  already_present="$(jq -r \
    --arg event "$event" \
    --arg cmd "$cmd_path" \
    '(.hooks[$event] // []) | map(.hooks[]?.command) | map(select(. == $cmd)) | length' \
    "$SETTINGS")"

  if [ "$already_present" -gt 0 ]; then
    echo "  → $event: $(basename "$cmd_path") already registered, skipping"
    rm -f "$settings_tmp"
    return
  fi

  if [ -n "$matcher" ]; then
    # Entry with matcher field
    jq \
      --arg event "$event" \
      --arg cmd "$cmd_path" \
      --arg matcher "$matcher" \
      '.hooks[$event] = ((.hooks[$event] // []) + [{"matcher": $matcher, "hooks": [{"type": "command", "command": $cmd, "timeout": 3000}]}])' \
      "$SETTINGS" > "$settings_tmp"
  else
    # Plain entry without matcher
    jq \
      --arg event "$event" \
      --arg cmd "$cmd_path" \
      '.hooks[$event] = ((.hooks[$event] // []) + [{"hooks": [{"type": "command", "command": $cmd, "timeout": 3000}]}])' \
      "$SETTINGS" > "$settings_tmp"
  fi

  mv "$settings_tmp" "$SETTINGS"
  echo "  ✓ $event: $(basename "$cmd_path") registered"
}

# ── Register all hooks ────────────────────────────────────────────────────────
echo ""
echo "Merging hooks into $SETTINGS ..."

merge_hook "PermissionRequest"  "~/.claude/hooks/slipstream-capture-permission.sh"
merge_hook "PreCompact"         "~/.claude/hooks/slipstream-capture-compaction.sh"
merge_hook "PostToolUseFailure" "~/.claude/hooks/slipstream-capture-errors.sh"
merge_hook "PostToolUse"        "~/.claude/hooks/slipstream-capture-reads.sh"    "Read|Glob"
merge_hook "Stop"               "~/.claude/hooks/slipstream-check-triggers.sh"
merge_hook "SessionStart"       "~/.claude/hooks/slipstream-check-triggers.sh"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  Slipstream installed successfully!                     │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""
echo "  Hook scripts : $HOOKS_DIR"
echo "  Commands     : $COMMANDS_DIR"
echo "  Data dir     : $DATA_DIR"
echo "  Settings     : $SETTINGS"
echo ""
echo "Run /slipstream in any Claude Code session to get started."
echo ""
