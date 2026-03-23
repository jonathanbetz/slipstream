# /slipstream-memory

Analyze Claude Code session transcripts to find user-level facts that should be persisted
in Claude's memory system but aren't yet. Propose additions to MEMORY.md and individual
memory files.

## State tracking

Uses `~/.slipstream/memory-state.json` with format `{"analyzed_session_ids": [...]}`.
Cumulative — never overwrite, always merge newly analyzed IDs.

## Step 0: Determine current project

Before reading any data:
1. Current project path = the working directory where Claude Code is open (`pwd`).
2. Project key = that path with every `/` replaced by `-`.
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).
4. Project sessions directory = `~/.claude/projects/<project-key>/`.

All analysis below is SCOPED TO THE CURRENT PROJECT only.

**CRITICAL RULES — READ BEFORE PROCEEDING:**
1. Run the pre-built script exactly as shown below. Do not write Python or shell code as a substitute.
2. Read the JSON output directly. Do not pipe it through `python3 -c`, `jq`, or any other command to extract fields — parse it in your head.
3. If the script is not found, stop and tell the user to run `./install.sh` from the slipstream repo.

## Step 1: Run analysis script

```bash
python3 ~/.claude/hooks/slipstream-analyze-memory.py
```

The script outputs JSON with:
- `total_sessions`, `already_analyzed`, `unanalyzed_count`, `unanalyzed_session_ids`
- `signals` — list of `{session_id, signal_type, matched, context}` objects

Show the mini-dashboard:
```
Memory module
  Total sessions:      <total_sessions>
  Already analyzed:    <already_analyzed>
  Unanalyzed:          <unanalyzed_count>
```

If `unanalyzed_count` < 2, say: "Not enough new sessions to analyze yet. Check back after a
few more sessions." and stop.

## Step 2: Find the memory system

Look for MEMORY.md in these locations, in order:
1. `~/.claude/memory/MEMORY.md`
2. `.claude/memory/MEMORY.md` in the current working directory
3. Any directory named `memory/` under `~/.claude/projects/`

If found, read MEMORY.md to understand what is already recorded and avoid duplicates.
Also read any existing memory files it references.

If not found, note that no memory system exists yet — proposals will include creating it.

## Step 3: Cluster findings

Use the `signals` array from the script output. Each entry has a `signal_type` of:
- `role` — user's job, expertise, or background
- `feedback` — how the user likes Claude to work
- `user` — knowledge signals (what they know well vs. what they're new to)

Group signals of the same type and deduplicate against existing memory files.

Only keep facts that:
- Describe the USER (their role, expertise, preferences, working style)
- Would be useful across ALL projects, not just one
- Are not already captured in existing memory files

Skip facts that describe the codebase, architecture, or conventions.

## Step 4: Present plan

Present a plan and **wait for user approval before writing anything**:

```
Memory improvement plan

  New memory entries (N):

  [user] user_role.md
    "User is a venture capitalist focused on B2B SaaS. Has technical background."
    Evidence: stated in 4 sessions across 3 projects

  [feedback] feedback_response_style.md
    "User prefers terse responses. No trailing summaries."
    Evidence: corrected verbose responses in 3 sessions

  [feedback] feedback_testing.md (UPDATE — add to existing)
    "User prefers integration tests over unit test mocks."
    Evidence: mentioned in 2 sessions
```

If no new facts were found, say so and stop.

## Step 5: Apply

**Before modifying any file**, create a timestamped backup in `~/.slipstream/backups/`:
```bash
mkdir -p ~/.slipstream/backups
TS=$(date -u +"%Y%m%dT%H%M%SZ")
# For any existing memory file being updated:
cp "<target-memory-file>" ~/.slipstream/backups/$(basename "<target-memory-file>").${TS}.bak
```
Report the backup path so the user knows where to find it.

For each approved entry:

1. Determine the memory directory (the directory containing MEMORY.md, or
   `~/.claude/memory/` if no memory system exists yet).

2. Determine file path: `<memory-dir>/<type>_<slug>.md`

3. Write with frontmatter format:
   ```markdown
   ---
   name: <descriptive name>
   description: <one-line description>
   type: <user|feedback|project|reference>
   ---

   <memory content>
   ```

4. Update MEMORY.md to add a pointer line for any new file:
   `- [filename.md](filename.md) — <one-line description>`

5. For updates to existing files: append the new fact with a brief context note.

## Step 5b: Record audit trail

For each file written or modified, append one line to `~/.slipstream/applied.jsonl`:
```bash
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg cmd "slipstream-memory" \
  --arg action "<memory-file-created|memory-file-updated>" \
  --arg target "<absolute path of memory file>" \
  --arg detail "<e.g. 'Created user_role.md from 4 sessions'>" \
  '{timestamp: $ts, command: $cmd, action: $action, target: $target, detail: $detail}' \
  >> ~/.slipstream/applied.jsonl
```

## Step 6: Update state

After applying all approved entries:

1. Read `~/.slipstream/memory-state.json` (or start with `{"analyzed_session_ids": []}`
   if it doesn't exist).
2. Merge the newly analyzed session IDs into `analyzed_session_ids` — append, never
   replace.
3. Write the merged object back to `~/.slipstream/memory-state.json`.
4. Read `~/.slipstream/cursors/<project-key>.json` (or `{}` if missing). Merge in:
   `{"last_memory_review": "<ISO 8601 timestamp of now>"}`. Write it back.

## Report

Print a summary:
```
Done.
  N memory files created
  M memory files updated
  MEMORY.md refreshed
```
