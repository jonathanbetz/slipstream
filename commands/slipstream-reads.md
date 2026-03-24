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

**CRITICAL RULES — READ BEFORE PROCEEDING:**
1. Run the pre-built script exactly as shown below. Do not write Python or shell code as a substitute.
2. Read the JSON output directly. Do not pipe it through `python3 -c`, `jq`, or any other command to extract fields — parse it in your head.
3. If the script is not found, stop and tell the user to run `./install.sh` from the slipstream repo.

## Step 1: Run analysis script

If the user provided a time argument (e.g. `7d`, `6h`), pass it as `--since <argument>`. Otherwise omit the flag.

```bash
python3 ~/.claude/hooks/slipstream-analyze-reads.py [--since DURATION]
```

The script outputs JSON with:
- `total`, `new_since_review`, `distinct_files`
- `orientation_files` — list of `{file_path, session_count, sessions, tool_names}` objects
  for files read in 3+ distinct sessions, sorted by priority then session_count

Show the mini-dashboard:
```
Reads module
  Total entries:       <total>
  New since review:    <new_since_review>
  Distinct files:      <distinct_files>
```

If `total` is 0, say:
> No read data captured yet. File reads are logged when Claude uses the Read or Glob
> tools. Run a few Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

Use the `orientation_files` array from the script output directly. These are files read
across 3+ distinct sessions and are the candidates for CLAUDE.md summarization.

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
