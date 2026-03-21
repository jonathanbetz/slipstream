# /slipstream-context

Analyze context compaction friction and propose CLAUDE.md improvements that reduce how
often Claude exhausts its context window. Present a plan, wait for approval, then apply.

---

## Step 1: Mini-dashboard

Load ~/.slipstream/compactions.jsonl. Load ~/.slipstream/.cursor.json.

Show:
- Total entries (line count)
- New since last review (current count minus compactions_line_count in .cursor.json; 0 if missing)
- Distinct projects affected (distinct meaningful directory names from the cwd field)

If the file is empty or missing, say:

> No compaction data captured yet. Compactions are logged when Claude's context window fills.
> Run a few longer Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

**Group by project:** Group compaction events by project (meaningful dir name from cwd —
last non-trivial path component, e.g. "myapp" from "/Users/alice/src/myapp").

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

## Step 5: Update cursor

Merge into ~/.slipstream/.cursor.json using jq — preserve all other fields:

```json
{"compactions_line_count": <current wc -l of compactions.jsonl>, "last_context_review": "<ISO 8601 now>"}
```

If .cursor.json does not exist, create it with just these two fields.

---

## Step 6: Report

```
Applied:
  J CLAUDE.md files updated across N projects
```
