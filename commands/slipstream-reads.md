# /slipstream-reads

Analyze orientation reads — files Claude re-reads every session to orient itself — and
propose CLAUDE.md summaries that eliminate those re-reads. Present a plan, wait for
approval, then apply.

---

## Step 0: Determine current project

Before reading any data:
1. Current project path = the working directory where Claude Code is open (`pwd`).
2. Project key = that path with every `/` replaced by `-`.
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).

All analysis below is SCOPED TO THE CURRENT PROJECT only.

## Step 1: Mini-dashboard

Load `~/.slipstream/projects/<project-key>/reads.jsonl`. Load the per-project cursor.

Show:
- Total entries (reads for this project)
- New since last review: count of entries with `.timestamp` > `last_reads_review`
  in per-project cursor (if no cursor, all entries are "new")
- Distinct files tracked (distinct file_path values among entries)

If the file is empty or missing, say:

> No read data captured yet. File reads are logged when Claude uses the Read or Glob
> tools. Run a few Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

**Find orientation reads:** Group entries by {project, file_path}.

Flag any {project, file_path} pair that appears across 3 or more distinct sessions
(distinct session_id values). These are "orientation reads" — files Claude repeatedly
reads at the start of sessions to understand the project.

**Prioritize by session frequency (most re-read first).** Within the same count, prefer:
1. CLAUDE.md files (re-reading context files is especially wasteful)
2. README files
3. Architecture or design documents
4. Configuration files that change rarely

**For each orientation file, propose:**
- Read the source file
- Extract 3–8 key facts Claude would need at the start of a session to orient itself
  without re-reading the file
- Add a summary of those facts to the project's root CLAUDE.md (or the nearest ancestor
  CLAUDE.md if the file lives in a subdirectory)
- The summary should be specific: for a config file, the key settings and their purpose;
  for an architecture doc, the module breakdown and data flow; for a README, the project
  purpose and structure

---

## Step 3: Present plan

```
Reads improvement plan
════════════════════════════════════════════════════════════════

── Orientation reads to pre-load ───────────────────────────────
  [project]  Summarize lib/auth/CLAUDE.md → root CLAUDE.md     read 6 sessions
  [project]  Summarize docs/architecture.md → CLAUDE.md        read 4 sessions
  [project]  Summarize .env.example → CLAUDE.md                read 3 sessions
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
cp "<target-CLAUDE.md>" ~/.slipstream/backups/CLAUDE.md.${TS}.bak
```
Report the backup path so the user knows where to find it.

For each approved summary:
1. Read the source file
2. Extract 3–8 key facts Claude would need to orient itself
3. Add them as a bullet list to the target CLAUDE.md under `## Quick reference` or
   `## Key facts` (create the section if needed; append to it if it already exists)
4. Do not paste the full file — summarize only what Claude needs to know
5. Keep it dense and scannable — bullet points, not prose
6. Do NOT rewrite existing CLAUDE.md content
7. Report: "Updated [path]: added summary of [source file] (read in N sessions)"

---

## Step 4b: Record audit trail

For each file written or modified, append one line to `~/.slipstream/applied.jsonl`:
```bash
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg cmd "slipstream-reads" \
  --arg action "claude-md-update" \
  --arg target "<absolute path of CLAUDE.md modified>" \
  --arg detail "<e.g. 'Added summary of docs/architecture.md (read 4 sessions)'>" \
  '{timestamp: $ts, command: $cmd, action: $action, target: $target, detail: $detail}' \
  >> ~/.slipstream/applied.jsonl
```

## Step 5: Update cursor

Merge into `~/.slipstream/cursors/<project-key>.json` using jq — preserve all other fields:

```json
{"last_reads_review": "<ISO 8601 now>"}
```

If the cursor does not exist, create it with just this field.

---

## Step 6: Report

```
Applied:
  N file summaries added across J CLAUDE.md files
  Estimated sessions where re-reads are eliminated: ~M
```
