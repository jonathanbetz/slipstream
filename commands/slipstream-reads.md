# /slipstream-reads

Analyze orientation reads — files Claude re-reads every session to orient itself — and
propose CLAUDE.md summaries that eliminate those re-reads. Present a plan, wait for
approval, then apply.

---

## Step 1: Mini-dashboard

Load ~/.slipstream/reads.jsonl. Load ~/.slipstream/.cursor.json.

Show:
- Total entries (line count)
- New since last review (current count minus reads_line_count in .cursor.json; 0 if missing)
- Distinct files tracked (distinct file_path values)
- Distinct projects (distinct meaningful directory names from the cwd field)

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

## Step 5: Update cursor

Merge into ~/.slipstream/.cursor.json using jq — preserve all other fields:

```json
{"reads_line_count": <current wc -l of reads.jsonl>, "last_reads_review": "<ISO 8601 now>"}
```

If .cursor.json does not exist, create it with just these two fields.

---

## Step 6: Report

```
Applied:
  N file summaries added across J CLAUDE.md files
  Estimated sessions where re-reads are eliminated: ~M
```
