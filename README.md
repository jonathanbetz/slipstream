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
| `/slipstream-memory` | Stop (transcript scan) | User-level facts repeated across sessions | MEMORY.md entries, memory files |
| `/slipstream-commands` | Stop (transcript scan) | Repeated Claude-orchestrated workflows | New slash command files |

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

This copies hook scripts to `~/.claude/hooks/`, command files to `~/.claude/commands/`, and merges hook entries into `~/.claude/settings.json`. Hooks fire across all your Claude Code projects. Safe to re-run — all merges are idempotent.

### Per-project install

If you only want Slipstream active in a specific project:

```bash
cd /path/to/your/project
/path/to/slipstream/install.sh --project
```

This writes hook entries into `.claude/settings.local.json` inside that project instead of your global settings. Hook scripts are still installed to `~/.claude/hooks/` (they need to live somewhere Claude Code can reach them), but they only fire when you're working in that project. You may want to add `.claude/settings.local.json` to your `.gitignore`.

---

## Usage

### Dashboard

Run `/slipstream` at any time to see what's been captured and which focused commands to run:

```
/slipstream
```

### Focused commands

Run these to analyze and fix a specific friction type:

| Command | What it fixes |
|---------|--------------|
| `/slipstream-permissions` | Allow-list entries, native tool swaps, reusable scripts |
| `/slipstream-context` | CLAUDE.md improvements to reduce context compaction |
| `/slipstream-errors` | Pre-flight checks for repeated tool failures |
| `/slipstream-reads` | CLAUDE.md summaries of files Claude re-reads every session |
| `/slipstream-corrections` | Rules derived from moments you corrected Claude |
| `/slipstream-memory` | Memory entries derived from user-level facts across sessions |
| `/slipstream-commands` | Slash commands derived from repeated orchestration workflows |

Each command shows a mini-dashboard for its module, proposes a ranked improvement plan,
waits for your approval, then applies changes directly.

### Automatic triggers

Two hooks keep Slipstream running in the background without any manual intervention:

**`SessionStart`** — at the start of every session, Slipstream checks whether any module is above its threshold and immediately alerts you. It also instructs Claude to set up an hourly `CronCreate` job for the session that silently re-checks thresholds every hour and runs the appropriate command when data has accumulated. Nothing is ever applied without your approval — each command presents a plan and waits for your go-ahead.

**`Stop`** — after each response, if thresholds are exceeded, a reminder is printed naming the specific commands to run.

Example alert:
```
[Slipstream]
  /slipstream-permissions   23 new events
  /slipstream-corrections    3 sessions
```

Thresholds per module:
- **Permissions:** 5 new events
- **Context:** 3 new compactions
- **Errors:** 3 new failures
- **Reads:** 10 new events
- **Corrections:** 2 unanalyzed sessions
- **Memory:** 2 unanalyzed sessions
- **Commands:** 3 unanalyzed sessions

A module is also surfaced if its last review was more than 7 days ago and it has any new data.

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
| `memory-state.json` | Analyzed session IDs for the memory module |
| `commands-state.json` | Analyzed session IDs for the commands module |

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

Slipstream is intentionally minimal — the hook scripts are short and readable, the slash commands are plain Markdown, and the analysis logic lives inside Claude's context window rather than in external code. Improvements to the analysis heuristics in the `commands/` files are especially welcome.

---

## License

MIT — see [LICENSE](LICENSE).
