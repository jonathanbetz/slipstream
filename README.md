# Slipstream

**Watches your Claude Code sessions. Finds friction. Gets out of the way.**

---

Claude Code asks permission before running commands, loses context mid-task, and re-reads the same files to orient itself at the start of each session. Each friction point is a small tax on your flow. Slipstream captures these events silently across every session and periodically reduces them — updating allow lists, improving CLAUDE.md files, and creating scripts for repeated workflows. Corrections — moments where you had to intervene and redirect Claude — are the most direct friction signal of all, and slipstream captures them from your session history automatically.

---

## How it works

Five hooks run in the background during every Claude Code session:

1. **Permission requests** are captured whenever Claude asks to run a command.
2. **Context compactions** are noted whenever the context window fills and is compacted.
3. **Tool failures** are recorded whenever a tool call fails.
4. **File reads** are tracked whenever Claude reads or globs files, revealing which files it re-reads to orient itself.
5. **Corrections** are mined from your session transcripts — moments where you had to intervene and redirect Claude are the most direct friction signal of all.

When the total event count crosses a threshold (20 events) or it has been 7 days since the last review, Claude Code surfaces a reminder at the end of the session. Running `/slipstream` then triggers a full analysis:

- Logs are parsed and grouped into actionable patterns
- A ranked improvement plan is presented, ordered by estimated friction eliminated
- After your approval, improvements are applied directly: settings files updated, CLAUDE.md files extended, scripts created

Nothing is sent anywhere. All data lives in `~/.slipstream/`.

---

## Modules

| Module | Hook | What it captures | What it improves |
|--------|------|-----------------|-----------------|
| Permissions | PermissionRequest | Commands Claude asked to run | Allow lists, native tool swaps, reusable scripts |
| Context | PreCompact | Context window compactions | CLAUDE.md depth, task-splitting guidance |
| Errors | PostToolUseFailure | Repeated tool failures | Pre-flight checks, broken dependencies |
| Reads | PostToolUse | Session-start orientation reads | CLAUDE.md summaries of key files |
| Corrections | Stop (transcript scan) | Moments you corrected Claude | .claude/rules files, CLAUDE.md additions |

---

## Install

**Requirements:** [Claude Code](https://claude.ai/code), [jq](https://stedolan.github.io/jq/)

```bash
# Install jq if needed
brew install jq          # macOS
sudo apt-get install jq  # Ubuntu/Debian

# Clone and install
git clone https://github.com/jonathanbetz/slipstream
cd slipstream
./install.sh
```

`install.sh` copies hook scripts to `~/.claude/hooks/`, command files to `~/.claude/commands/`, and merges the required hook entries into `~/.claude/settings.json`. It is safe to run multiple times — all merges are idempotent.

---

## Usage

### Automatic triggers

After install, Slipstream runs silently in the background. It will remind you to run `/slipstream` when:

- **20 or more** new friction events have been captured since the last review, or
- **7 or more days** have passed since the last review and at least 5 new events exist

The reminder appears as a message at the end of a session or the start of the next one.

### Manual review

At any time in Claude Code, run:

```
/slipstream
```

This starts the full analysis and improvement workflow. Claude will:
1. Show a dashboard of captured events
2. Analyze all five friction modules
3. Present a ranked improvement plan
4. Apply approved changes (allow lists, CLAUDE.md additions, scripts)
5. Update the review cursor so the threshold resets

---

## Data

All data is stored locally in `~/.slipstream/`:

| File | Contents |
|------|----------|
| `permissions.jsonl` | Permission request events (timestamp, session, cwd, tool, input) |
| `compactions.jsonl` | Context compaction events (timestamp, session, cwd) |
| `errors.jsonl` | Tool failure events (timestamp, session, cwd, tool, input) |
| `reads.jsonl` | File read events (timestamp, session, cwd, tool, file_path) |
| `.cursor.json` | Last-review state (line counts, timestamp) |
| `corrections-state.json` | Analyzed session IDs (cumulative, prevents re-processing) |

Nothing is uploaded, synced, or shared. The hooks write append-only JSONL files. The logs grow slowly — a busy week of Claude Code usage produces a few hundred lines across all files.

---

## Uninstall

```bash
cd slipstream
./uninstall.sh
```

The uninstaller removes hook scripts from `~/.claude/hooks/`, command files from `~/.claude/commands/`, and filters slipstream entries from `~/.claude/settings.json`. It then asks whether to delete the `~/.slipstream/` data directory.

---

## Contributing

Slipstream is intentionally minimal — the hook scripts are short and readable, the slash commands are plain Markdown, and the analysis logic lives inside Claude's context window rather than in external code. Improvements to the analysis heuristics in `commands/slipstream.md` are especially welcome.

---

## License

MIT — see [LICENSE](LICENSE).
