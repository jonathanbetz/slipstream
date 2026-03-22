#!/bin/bash
# SessionStart hook — fires at the beginning of every Claude Code session.
# Silent: ensures the per-project data directory exists, then exits.
# Threshold alerts appear at the end of conversations via the Stop hook.

set -euo pipefail

DATA_DIR="$HOME/.slipstream"

trap 'exit 0' ERR

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || echo "")"
[ -z "$CWD" ] && CWD="$(pwd)"

PROJECT_KEY="$(printf '%s' "$CWD" | sed 's|/|-|g')"

mkdir -p "$DATA_DIR/projects/$PROJECT_KEY" "$DATA_DIR/cursors"

exit 0
