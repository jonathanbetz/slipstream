# /slipstream

You are running the Slipstream friction-reduction workflow. Work through the phases below in order. Be analytical, concrete, and terse. Do not ask for confirmation between phases unless instructed.

---

## Phase 1: Dashboard

Load the four Slipstream log files from `~/.slipstream/`:
- `permissions.jsonl`
- `compactions.jsonl`
- `errors.jsonl`
- `reads.jsonl`

Also load `~/.slipstream/.cursor.json` for last-review state.

**If all four log files are empty or missing:**
Tell the user:
> Slipstream is installed but hasn't captured data yet. Friction events will appear in ~/.slipstream/ as you use Claude Code. Run /slipstream again after a few sessions.

Stop here — do not proceed to later phases.

**Otherwise**, count total events across all logs and display the dashboard:

```
Slipstream — friction captured since [date of earliest entry across all logs]

  Permissions   N events  (M projects, L sessions)
  Compactions   N events  (M projects)
  Errors        N events  (M tools)
  Reads         N events  (M files, L projects)
  Corrections   N sessions analyzed  (M corrections found)

  Last review: [last_review_timestamp from .cursor.json, or "never"]
```

Where:
- projects = distinct meaningful directory names from the `cwd` field (use the last meaningful component, not the full path)
- sessions = distinct `session_id` values
- files = distinct `file_path` values in reads.jsonl
- tools = distinct `tool_name` values in errors.jsonl

---

## Phase 2: Five-module analysis

Run all five analyses before presenting anything. Then present all findings together.

---

### Module A: Permission friction

Analyze `permissions.jsonl`.

**Step 1 — Group and normalize**

Group entries by `{project, normalized_pattern}`:
- `project` = meaningful directory name from `cwd` (last non-trivial path component, e.g. "myapp" from "/Users/alice/src/myapp")
- `normalized_pattern` = normalize Bash commands by stripping variable arguments:
  - Replace quoted strings, file paths, and version numbers with `*`
  - If a command varies across sessions in its arguments, append `*` to the base command
  - Example: `npm install lodash` and `npm install react` both normalize to `npm install *`
  - Example: `git commit -m "fix bug"` normalizes to `git commit *`
  - Keep commands that are always identical as-is

**Step 2 — Flag allow-list candidates**

Flag a `{project, normalized_pattern}` if ALL of these are true:
- Appears in 3 or more distinct sessions
- Not already present in `~/.claude/settings.json` or the project's `.claude/settings.json` allow list
- The command looks safe (not rm -rf, not destructive system commands)

**Cross-project candidates:** if the same normalized pattern appears in 2+ distinct projects, flag it as a global `~/.claude/settings.json` candidate instead of per-project.

**Step 3 — Flag native tool substitutions**

Look for Bash commands that Claude Code has a native equivalent for:
- `grep` / `grep -r` → prefer native `Grep` tool
- `find` → prefer native `Glob` tool
- `cat`, `head`, `tail` → prefer native `Read` tool
- `echo > file`, `tee` → prefer native `Write` tool
- `sed -i` → prefer native `Edit` tool

If a native-substitute command appears in 2+ sessions in the same project, flag it for a CLAUDE.md note: "Prefer [NativeTool] over [bashcmd] for [purpose]."

**Step 4 — Flag script opportunities**

Look for:
- **Session clusters:** 3 or more Bash permission requests within 15 minutes in the same session, appearing across 2 or more sessions → suggest a reusable script
- **Repeated complex commands:** same command appearing in 4+ sessions, OR any command longer than 60 characters appearing in 2+ sessions → suggest a script
- **Cross-project duplicates:** same cluster pattern appearing in 2+ projects → suggest a `~/bin/` script

For each script opportunity, propose:
- Script name and location (`scripts/` in the project, `~/.claude/hooks/`, or `~/bin/`)
- Script content derived from the distinct commands in the cluster
- A single allow-list entry that covers the script, replacing multiple individual entries
- Whether a slash command wrapper makes sense

---

### Module B: Context friction

Analyze `compactions.jsonl`.

**Step 1 — Group by project**

Group compaction events by project (meaningful dir name from `cwd`).

**Step 2 — Flag high-compaction projects**

Flag any project with 3 or more total compaction events.

Also note any projects with multiple compactions in the same session (same `session_id`) — this indicates very deep tasks that exhaust context repeatedly.

**Step 3 — Suggest improvements**

For each flagged project, suggest one or more of:
- **Architecture overview:** "Add an architecture overview section to [project]/CLAUDE.md so Claude can orient quickly without reading many files"
- **Task-splitting guidance:** "Add a note to CLAUDE.md suggesting that long tasks be broken into focused sessions. Example: '## Working style / Break large tasks into focused sessions — prefer smaller commits over marathon sessions.'"
- **Reference content:** "Frequently accessed reference content (e.g. API schemas, config structures) should be summarized in CLAUDE.md rather than re-read from files each session"

---

### Module C: Error friction

Analyze `errors.jsonl`.

**Step 1 — Group by pattern**

Group PostToolUseFailure entries by `{project, tool_name, base_command}`:
- `base_command` = for Bash tool failures, the first word(s) of the command (the executable + subcommand, e.g. "npm run e2e" not the full args)
- For other tools (Edit, Write, etc.), group by tool_name alone

**Step 2 — Flag repeated failures**

Flag any `{project, tool_name, base_command}` with 2 or more failures.

**Step 3 — Suggest fixes**

- **Bash failures:** Suggest adding a pre-flight note to the project's CLAUDE.md: "Before running [command], ensure [environment condition]. Example: [correct invocation]"
- **Repeated Edit/Write failures:** May indicate file permission issues or incorrect paths — suggest noting the correct path convention in CLAUDE.md
- **Any tool with 4+ failures:** Prioritize highly; this is a systemic issue

---

### Module D: Read friction

Analyze `reads.jsonl`.

**Step 1 — Find orientation reads**

Find `{project, file_path}` pairs that appear across 3 or more distinct sessions (`session_id` values).

These are files Claude re-reads at the start of sessions to orient itself — each re-read is avoidable friction.

**Step 2 — Prioritize**

Sort by session frequency (most re-read files first). Prioritize:
1. Files already named CLAUDE.md (deeply re-read project context)
2. README files
3. Architecture or design documents
4. Configuration files that change rarely

**Step 3 — Suggest improvements**

For each frequently re-read file, suggest:
> "Add a summary of [file]'s key facts to [project]/CLAUDE.md. This file was read in N sessions."

Be specific: the summary should capture the facts Claude needs (e.g. for a config file: the key settings and their purpose; for an architecture doc: the module breakdown and data flow).

---

### Module E: Correction patterns

Find session transcripts not yet analyzed:
- List all files under `~/.claude/projects/` matching `*.jsonl`
- Read `~/.slipstream/corrections-state.json` to get `analyzed_session_ids` (default empty array)
- Process only transcripts whose filename (session ID) is NOT in that list
- Skip transcripts with fewer than 4 turns (too short to contain meaningful corrections)

For each unanalyzed transcript, read it line by line. Each line is a JSON object representing one conversation turn with fields like `role` ("user" or "assistant") and `content`.

Identify correction turns: a user turn that follows an assistant turn and contains signals like:
- Explicit negation: "no", "don't", "stop", "wait", "actually", "that's not", "that's wrong"
- Redirection: "instead", "rather", "what I meant", "I said", "I meant"
- Undo requests: "revert", "undo", "go back", "remove what you just"
- Re-statement of original request with modifications

For each correction found, record:
- `project`: derived from the transcript's directory path under `~/.claude/projects/`
- `session_id`: the transcript filename without extension
- `assistant_turn`: the assistant message that was corrected (first 300 chars)
- `correction`: the user's correction turn (first 300 chars)
- `theme`: briefly what the correction was about

After collecting all corrections across all unanalyzed transcripts:
- Group by project
- Look for recurring themes: same type of correction appearing in 2+ sessions for the same project
- Classify each theme:
  - `convention` — code style, naming, formatting the AI kept getting wrong
  - `scope` — doing too much, too little, touching wrong files
  - `workflow` — wrong order of operations, skipped steps
  - `architecture` — structural decisions, where things belong
  - `domain` — facts about the project the AI didn't know
- For recurring themes (2+ sessions), generate a concrete mitigation:
  - `convention`/`workflow`/`scope` → a `.claude/rules/<slug>.md` file with a clear rule
  - `architecture`/`domain` → an addition to the appropriate CLAUDE.md (root or subdirectory)
- For one-off corrections, group into broader patterns if 3+ exist, otherwise skip (too noisy)

Identify the right file location for each mitigation:
- Project-wide rules → `.claude/rules/<slug>.md` in the project root
- Directory-specific facts → the closest ancestor CLAUDE.md for the files involved
- Cross-cutting conventions → root `CLAUDE.md`

Include in the unified plan under a **Corrections** section.

---

## Phase 3: Unified improvement plan

Present a single ranked improvement plan, ordered by estimated friction-sessions eliminated. Group by module. Use this exact format:

```
Slipstream improvement plan
════════════════════════════════════════════════════════════════

── Permissions (eliminates ~N prompts/week) ────────────────────
  [project]  Allow: Bash(npm test), Bash(git commit *)   8 sessions each
  [global]   Allow: Bash(gh run list *)                  5 sessions, 3 projects
  [project]  CLAUDE.md: prefer Grep over grep            4 sessions
  [project]  New script: scripts/deploy.sh               replaces 4-cmd cluster, 6 sessions

── Context (reduces compaction in N projects) ──────────────────
  [project]  CLAUDE.md: add architecture overview        compacted 7 times
  [project]  CLAUDE.md: note task-splitting strategy     3 same-session compactions

── Errors (eliminates N repeated failures) ─────────────────────
  [project]  CLAUDE.md: pre-flight note for npm run e2e  failed 4 times

── Reads (pre-load N orientation files) ────────────────────────
  [project]  CLAUDE.md: summarize lib/auth/CLAUDE.md    read in 6 sessions

── Corrections (from N sessions, M corrections) ────────────────
  [project]  .claude/rules/no-scope-creep.md            3 sessions, convention
  [project]  CLAUDE.md: add domain fact about auth flow  2 sessions, domain
```

After displaying the plan, say:

> Review the plan above. Remove any items you don't want applied, then say "apply", "go", or "do it" to proceed. Or say "skip" to exit without changes.

Wait for user response. If the user edits the plan or says to skip certain items, respect those edits. Apply only what the user approves.

---

## Phase 4: Apply

Work through the approved items in this order:
1. **Scripts first** (new scripts affect what allow entries to create)
2. **Allow-list additions** (edit settings files)
3. **CLAUDE.md updates** (add minimal targeted sections)

For each item, announce what you are about to do, do it, then confirm what changed.

### Scripts

- Write the script to the proposed location
- Run `chmod +x` on it
- If a slash command wrapper was proposed, create it in `~/.claude/commands/` or `.claude/commands/`
- Report: "Created [path]"

### Allow-list additions

Load the target settings file (`~/.claude/settings.json` for global, `[project]/.claude/settings.json` for per-project).

Add each approved command to the `permissions.allow` array. Use this structure:
```json
{
  "permissions": {
    "allow": [
      "Bash(npm test)",
      "Bash(git commit *)"
    ]
  }
}
```

If the file doesn't have a `permissions` key, add it. Preserve all existing structure. Never remove existing allow entries.

Idempotent: skip if the entry is already present.

Report: "Updated [path]: added N allow entries"

### CLAUDE.md updates

Load the target CLAUDE.md (create it if it doesn't exist with a minimal header).

Make minimal, targeted additions:
- **Tool preference notes:** Add under a `## Tool preferences` heading (create if needed). Example: "Use the Grep tool instead of running grep via Bash."
- **Pre-flight notes:** Add under a `## Environment notes` heading (create if needed). Example: "Before running npm run e2e, ensure the dev server is running: npm run dev"
- **Architecture summaries:** Add under a `## Architecture` heading (create if needed). Keep summaries to 3–8 bullet points.
- **Working-style notes:** Add under a `## Working style` heading (create if needed).

Do NOT rewrite existing content. Add new sections at the end if the heading doesn't exist, or append to an existing section if the heading is already there.

Report: "Updated [path]: added [section name]"

### Orientation file summaries

When adding a summary of a frequently-read file to CLAUDE.md:
1. Read the source file
2. Extract 3–8 key facts Claude would need to orient itself
3. Add them as a bullet list under `## Key files` or a project-specific heading in CLAUDE.md
4. Do not paste the full file — summarize only what Claude needs to know

### Correction mitigations

For `.claude/rules/<slug>.md` files:
- Write the file to the proposed path
- Include a header comment: `# Learned from N corrections across M sessions`
- Keep the rule concise and actionable (what to do, not what not to do where possible)
- Run `chmod +x` is not needed for .md files

For CLAUDE.md additions from correction analysis:
- Add under an appropriate existing section if one exists, or create a new section
- Keep additions terse — one to three bullet points per theme
- Do NOT rewrite existing content

Report: "Created [path]" or "Updated [path]: added correction rule"

---

## Phase 5: Update cursor

Write `~/.slipstream/.cursor.json` with the current state:

```json
{
  "last_review_timestamp": "<current time in ISO 8601 UTC, e.g. 2026-03-21T14:30:00Z>",
  "permissions_line_count": <number of lines in permissions.jsonl, or 0 if missing>,
  "compactions_line_count": <number of lines in compactions.jsonl, or 0 if missing>,
  "errors_line_count": <number of lines in errors.jsonl, or 0 if missing>,
  "reads_line_count": <number of lines in reads.jsonl, or 0 if missing>,
  "corrections_analyzed_sessions": ["<session_id_1>", "<session_id_2>"]
}
```

Use `wc -l` to count lines.

Also write/merge `~/.slipstream/corrections-state.json`:

```json
{
  "analyzed_session_ids": ["<all session IDs processed so far, cumulative>"]
}
```

This must be cumulative — always merge with existing `analyzed_session_ids`, never overwrite. Read the existing file first (if it exists), merge the newly processed session IDs into the array, then write the result back.

---

## Phase 6: Final report

```
Applied:
  ✓ N allow-list entries across M projects
  ✓ K scripts created
  ✓ J CLAUDE.md files updated

Estimated reduction: ~X friction events per week eliminated.
Next review triggers after 20 new events or 7 days.
```

Compute `X` as: (allow-list entries × avg sessions per entry) + (scripts × sessions replaced) + (CLAUDE.md additions × estimated sessions saved). Be explicit but reasonable in the estimate.
