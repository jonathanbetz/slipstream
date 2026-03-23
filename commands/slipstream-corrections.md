# /slipstream-corrections

Mine session transcripts for moments where you corrected Claude, identify recurring
patterns, and generate concrete rules. Present a plan, wait for approval, then apply.

---

## Step 0: Determine current project

Before reading any data:
1. Current project path = the working directory where Claude Code is open (`pwd`).
2. Project key = that path with every `/` replaced by `-`
   (e.g. `/Users/alice/src/myapp` → `-Users-alice-src-myapp`).
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).
4. Project sessions directory = `~/.claude/projects/<project-key>/`.

All analysis below is SCOPED TO THE CURRENT PROJECT only.

## Step 1: Run analysis script

```bash
python3 ~/.claude/hooks/slipstream-analyze-corrections.py
```

The script outputs JSON with:
- `total_sessions` — all session files found for this project
- `already_analyzed` — sessions already processed
- `unanalyzed_count` — sessions not yet analyzed
- `unanalyzed_session_ids` — list of session IDs to process
- `corrections` — list of `{session_id, assistant_text, correction_text, keywords}` objects

Show the mini-dashboard:
```
Corrections module
  Total sessions:      <total_sessions>
  Already analyzed:    <already_analyzed>
  Unanalyzed:          <unanalyzed_count>
```

If `unanalyzed_count` is 0, say:
> All sessions analyzed. Nothing new to review.

Stop here.

If `unanalyzed_count` < 2, say:
> Only N unanalyzed session(s) — below the threshold of 2. Check back after a few more sessions.

Stop here.

---

## Step 2: Analysis

Use the `corrections` array from the script output. Each entry is a user turn that
followed an assistant turn and contained correction language.

**Group and classify:** Group by recurring themes across sessions:
- convention — code style, naming, formatting the assistant kept getting wrong
- scope — doing too much, too little, or touching wrong files
- workflow — wrong order of operations, skipped steps
- architecture — structural decisions, where things belong
- domain — facts about the project the assistant didn't know

**Generate mitigations:**
- Recurring themes (2+ sessions):
  - convention / workflow / scope → a .claude/rules/<slug>.md file with a clear rule
  - architecture / domain → an addition to the appropriate CLAUDE.md
- One-off corrections: only include if 3+ one-offs can be grouped into a coherent broader
  rule; otherwise skip

**Identify the right file location for each mitigation:**
- Project-wide rules → .claude/rules/<slug>.md in the project root
- Directory-specific facts → the closest ancestor CLAUDE.md for the files involved
- Cross-cutting conventions → root CLAUDE.md

---

## Step 3: Present plan

```
Corrections improvement plan
════════════════════════════════════════════════════════════════

── [project-name] ──────────────────────────────────────────────
  .claude/rules/no-scope-creep.md        3 sessions, scope
    Evidence: sessions abc123, def456, ghi789
    Rule: "Only modify files explicitly mentioned in the task. Do not refactor
           adjacent code unless asked."

  CLAUDE.md: add domain fact about auth flow   2 sessions, domain
    Evidence: sessions abc123, jkl012
    Addition: "Auth tokens are stored in Redis with a 24h TTL. Never read them
               from the database — always check Redis first."
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

**Rules files (.claude/rules/<slug>.md):**
- Write the file to the proposed path (create .claude/rules/ directory if needed)
- Include a header: `# Learned from N corrections across M sessions`
- Keep the rule concise and actionable — one rule per file, no essays, what to do not
  what not to do where possible
- Report: "Created [path]"

**CLAUDE.md additions:**
- Load the target CLAUDE.md (create with minimal header if it doesn't exist)
- Add under an appropriate existing section if one exists, or create a new section
- Keep additions terse — one to three bullet points per theme
- Do NOT rewrite existing content
- Report: "Updated [path]: added correction-derived note"

---

## Step 4b: Record audit trail

For each file written or modified, append one line to `~/.slipstream/applied.jsonl`:
```bash
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg cmd "slipstream-corrections" \
  --arg action "<rule-created|claude-md-update>" \
  --arg target "<absolute path of file written>" \
  --arg detail "<brief description, e.g. 'Added no-scope-creep rule from 3 sessions'>" \
  '{timestamp: $ts, command: $cmd, action: $action, target: $target, detail: $detail}' \
  >> ~/.slipstream/applied.jsonl
```

## Step 5: Update state

**Update cursor** — merge into `~/.slipstream/cursors/<project-key>.json` using jq, preserve all other fields:

```json
{"last_corrections_review": "<ISO 8601 now>"}
```

**Update corrections-state.json** — CUMULATIVE, never overwrite:
1. Read ~/.slipstream/corrections-state.json (default {"analyzed_session_ids": []})
2. Merge the newly analyzed session IDs into the existing array
3. Write back:

```json
{"analyzed_session_ids": ["<all previously analyzed> + <newly analyzed>"]}
```

Example jq command:
```bash
jq -s '{"analyzed_session_ids": (.[0].analyzed_session_ids + .[1].analyzed_session_ids | unique)}' \
  ~/.slipstream/corrections-state.json - <<< '{"analyzed_session_ids": ["new1","new2"]}' \
  > /tmp/cs.tmp && mv /tmp/cs.tmp ~/.slipstream/corrections-state.json
```

---

## Step 6: Report

```
Applied:
  N rules created (.claude/rules/)
  J CLAUDE.md files updated
  M sessions analyzed (cumulative total: T)
```
