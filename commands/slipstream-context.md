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

## Step 1: Mini-dashboard

Load ~/.slipstream/compactions.jsonl filtered to entries where `.cwd` starts with the
current project path. Load the per-project cursor.

Show:
- Total filtered entries (compactions for this project)
- New since last review: count of filtered entries with `.timestamp` > `last_context_review`
  in per-project cursor (if no cursor, all entries are "new")

If the file is empty or missing, say:

> No compaction data captured yet. Compactions are logged when Claude's context window fills.
> Run a few longer Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

**Group by project:** Group compaction events by project using the cwd path relative to
$HOME (e.g. "src/myapp" from "/Users/alice/src/myapp"). Use the full relative path —
never basename alone — to avoid collisions across projects that share a directory name.

**Flag high-compaction projects:**
- 3 or more total compaction events for the same project, OR
- 2 or more compactions within a single session (same session_id) — this indicates tasks
  that exhaust context repeatedly

For same-session multiple compactions, note the session_id and approximate time range
(earliest and latest timestamp in that session).

**For each flagged project, propose one or more improvements:**

1. If the project has no architecture overview section in its CLAUDE.md:
   - Propose adding one — a section summarizing the key facts Claude needs to orient itself
     at the start of a session, so it doesn't need to re-read many files
   - The overview should cover: project purpose, major modules/directories, key conventions,
     entry points

2. If there were same-session multiple compactions (2+):
   - Propose adding a working-style note to CLAUDE.md: "Break large tasks into focused
     sessions — prefer smaller commits over marathon sessions."

3. If compactions are concentrated in a specific subdirectory (same cwd subdirectory across
   multiple events):
   - Propose adding targeted context about that area to the nearest ancestor CLAUDE.md in
     that subdirectory

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
