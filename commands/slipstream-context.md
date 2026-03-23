# /slipstream-context

Analyze context compaction friction and propose CLAUDE.md improvements that reduce how
often Claude exhausts its context window. Present a plan, wait for approval, then apply.

---

## Step 0: Determine current project

Before reading any data:
1. Current project path = the working directory where Claude Code is open (`pwd`).
2. Project key = that path with every `/` replaced by `-`.
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).

All analysis below is SCOPED TO THE CURRENT PROJECT only.

**CRITICAL RULES — READ BEFORE PROCEEDING:**
1. Run the pre-built script exactly as shown below. Do not write Python or shell code as a substitute.
2. Read the JSON output directly. Do not pipe it through `python3 -c`, `jq`, or any other command to extract fields — parse it in your head.
3. If the script is not found, stop and tell the user to run `./install.sh` from the slipstream repo.

## Step 1: Run analysis script

```bash
python3 ~/.claude/hooks/slipstream-analyze-context.py
```

The script outputs JSON with:
- `total`, `new_since_review`, `distinct_sessions`
- `sessions` — list of `{session_id, count, first, last, cwds, multi_compaction}` objects
- `high_compaction_sessions` — session IDs with 2+ compactions
- `has_high_compaction` — true if total >= 3 or any multi-compaction sessions exist

Show the mini-dashboard:
```
Context module
  Total compactions:   <total>
  New since review:    <new_since_review>
  Sessions affected:   <distinct_sessions>
```

If `total` is 0, say:
> No compaction data captured yet. Compactions are logged when Claude's context window fills.
> Run a few longer Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

Use the script output directly.

**Flag high-compaction projects:**
- `has_high_compaction` is true (3+ total, or 2+ in a single session)

**For the project, propose one or more improvements:**

1. If the project has no architecture overview section in its CLAUDE.md:
   - Propose adding one — a section summarizing the key facts Claude needs to orient itself
     at the start of a session, so it doesn't need to re-read many files
   - The overview should cover: project purpose, major modules/directories, key conventions,
     entry points

2. If `high_compaction_sessions` is non-empty (2+ compactions in a single session):
   - Propose adding a working-style note to CLAUDE.md: "Break large tasks into focused
     sessions — prefer smaller commits over marathon sessions."

3. If compactions are concentrated in sessions with a specific subdirectory cwd (visible
   in the `cwds` field of high-compaction sessions):
   - Propose adding targeted context about that area to the nearest ancestor CLAUDE.md
     in that subdirectory

---

## Step 3: Present plan

```
Context improvement plan
════════════════════════════════════════════════════════════════

── High-compaction projects ────────────────────────────────────
  [project]  CLAUDE.md: add architecture overview     compacted 7 times
  [project]  CLAUDE.md: add task-splitting note       3 same-session compactions
  [project/subdir]  CLAUDE.md: add subdir context     5 compactions in this area
```

After the plan, say:

> Review the plan above. Remove any items you don't want applied, then say "apply",
> "go", or "do it" to proceed. Or say "skip" to exit without changes.

Wait for user response.

---

## Step 4: Apply

**Before modifying any file**, create a timestamped backup in `~/.slipstream/backups/`:
```bash
mkdir -p ~/.slipstream/backups
TS=$(date -u +"%Y%m%dT%H%M%SZ")
# For each CLAUDE.md being modified:
cp "<target-CLAUDE.md>" ~/.slipstream/backups/CLAUDE.md.${TS}.bak
```
Report the backup path so the user knows where to find it.

For each approved CLAUDE.md addition:
- Load the target CLAUDE.md (create with minimal header if it doesn't exist)
- Add under an appropriate heading:
  - Architecture overview → `## Architecture`
  - Task-splitting note → `## Working style`
  - Subdir context → `## Context` or a project-specific heading
- Keep additions terse — the goal is orientation facts, not essays. 3–8 bullet points for
  architecture; 1–2 sentences for working-style notes
- Do NOT rewrite existing content
- Report: "Updated [path]: added [section name]"

---

## Step 4b: Record audit trail

For each file written or modified, append one line to `~/.slipstream/applied.jsonl`:
```bash
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg cmd "slipstream-context" \
  --arg action "claude-md-update" \
  --arg target "<absolute path of CLAUDE.md modified>" \
  --arg detail "<section added, e.g. 'Added Architecture overview'>" \
  '{timestamp: $ts, command: $cmd, action: $action, target: $target, detail: $detail}' \
  >> ~/.slipstream/applied.jsonl
```

## Step 5: Update cursor

Merge into `~/.slipstream/cursors/<project-key>.json` using jq — preserve all other fields:

```json
{"last_context_review": "<ISO 8601 now>"}
```

If the cursor does not exist, create it with just this field.

---

## Step 6: Report

```
Applied:
  J CLAUDE.md files updated across N projects
```
