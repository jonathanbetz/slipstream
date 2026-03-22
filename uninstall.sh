#!/bin/bash
# uninstall.sh — Slipstream uninstaller
# Removes hook scripts, command files, and hook entries from settings.json.
# Optionally removes the ~/.slipstream/ data directory.

set -e

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS="$CLAUDE_DIR/settings.json"
DATA_DIR="$HOME/.slipstream"

echo ""
echo "┌─────────────────────────────────────────┐"
echo "│  Uninstalling Slipstream...             │"
echo "└─────────────────────────────────────────┘"
echo ""

# ── Remove hook scripts ───────────────────────────────────────────────────────
echo "Removing hook scripts from $HOOKS_DIR ..."
for f in "$HOOKS_DIR"/slipstream-*.py; do
  if [ -f "$f" ]; then
    rm -f "$f"
    echo "  ✓ Removed $(basename "$f")"
  fi
done
if [ -d "$HOOKS_DIR/slipstream" ]; then
  rm -rf "$HOOKS_DIR/slipstream"
  echo "  ✓ Removed slipstream/ package"
fi

# ── Remove command files ──────────────────────────────────────────────────────
echo ""
echo "Removing commands from $COMMANDS_DIR ..."
for f in "$COMMANDS_DIR"/slipstream*.md; do
  if [ -f "$f" ]; then
    rm -f "$f"
    echo "  ✓ Removed $(basename "$f")"
  fi
done

# ── Remove hook entries from settings.json ────────────────────────────────────
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  echo ""
  echo "Removing slipstream hook entries from $SETTINGS ..."

  SETTINGS_TMP="$(mktemp)"

  # For each hook event, filter out entries whose hooks[].command contains "slipstream"
  jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= map(
          select(
            (.hooks // [] | map(.command) | map(test("slipstream")) | any) | not
          )
        )
        | select(.value | length > 0)
      )
    else . end
  ' "$SETTINGS" > "$SETTINGS_TMP"

  mv "$SETTINGS_TMP" "$SETTINGS"
  echo "  ✓ Hook entries removed from settings.json"
else
  echo ""
  echo "  Skipping settings.json cleanup (file not found or jq not available)"
fi

# ── Optionally remove data directory ─────────────────────────────────────────
echo ""
if [ -d "$DATA_DIR" ]; then
  printf "Remove data directory %s? This deletes all captured friction logs. [y/N] " "$DATA_DIR"
  read -r CONFIRM
  case "$CONFIRM" in
    [yY]|[yY][eE][sS])
      rm -rf "$DATA_DIR"
      echo "  ✓ Removed $DATA_DIR"
      ;;
    *)
      echo "  Kept $DATA_DIR — your friction logs are preserved."
      ;;
  esac
else
  echo "  Data directory $DATA_DIR not found, nothing to remove."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Slipstream has been uninstalled."
echo ""
