# /slipstream-corrections

Mine session transcripts for moments where you corrected Claude, identify recurring
patterns, and generate concrete rules. Present a plan, wait for approval, then apply.

---

## Step 1: Mini-dashboard

- List all *.jsonl files under ~/.claude/projects/
- Load ~/.slipstream/corrections-state.json — get analyzed_session_ids (default [])
- Count unanalyzed sessions: files whose stem (filename without extension) is NOT in
  analyzed_session_ids
- Show:
  - Total session files found
  - Unanalyzed count
  - Projects covered (distinct directory names from the path under ~/.claude/projects/)

If no unanalyzed sessions exist, say:

> All sessions analyzed. Nothing new to review.

Stop here.

If fewer than 2 unanalyzed sessions exist, say:

> Only N unanalyzed session(s) — below the threshold of 2. Check back after a few more
> sessions.

Stop here.

---

## Step 2: Analysis

Read each unanalyzed transcript (*.jsonl file). Skip transcripts with fewer than 4 turns
(too short to contain meaningful corrections). Each line in a transcript is a JSON object
with a role field ("user" or "assistant") and content.

**Identify correction turns:** A user turn that follows an assistant turn and contains:
- Explicit negation: "no", "don't", "stop", "wait", "actually", "that's not", "that's wrong"
- Redirection: "instead", "rather", "what I meant", "I said", "I meant"
- Undo requests: "revert", "undo", "go back", "remove what you just"
- Re-statement of the original request with modifications implying the first response missed
  the mark

For each correction found, record:
- project: derived from the directory path under ~/.claude/projects/
- session_id: the transcript filename without extension
- assistant_turn: the assistant message that was corrected (first 300 chars)
- correction: the user's correction turn (first 300 chars)
- theme: briefly what the correction was about

**Group and classify:** After collecting corrections across all unanalyzed transcripts:
- Group by project
- Look for recurring themes: same type of correction in 2+ sessions for the same project
- Classify each theme:
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
  rule; otherwise skip (too noisy to act on)

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

## Step 5: Update state

**Update cursor** — merge into ~/.slipstream/.cursor.json using jq, preserve all other fields:

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
