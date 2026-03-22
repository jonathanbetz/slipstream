# /slipstream-errors

Analyze repeated tool failures and propose pre-flight notes that prevent them. Present a
plan, wait for approval, then apply.

---

## Step 0: Determine current project

Before reading any data:
1. Current project path = the working directory where Claude Code is open (`pwd`).
2. Project key = that path with every `/` replaced by `-`.
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).

All analysis below is SCOPED TO THE CURRENT PROJECT only.

## Step 1: Mini-dashboard

Load `~/.slipstream/projects/<project-key>/errors.jsonl`. Load the per-project cursor.

Show:
- Total entries (errors for this project)
- New since last review: count of entries with `.timestamp` > `last_errors_review`
  in per-project cursor (if no cursor, all entries are "new")
- Distinct tools involved (distinct tool_name values among entries)

If the file is empty or missing, say:

> No error data captured yet. Tool failures are logged when a hook or tool call exits
> non-zero. Run a few Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

**Group by pattern:** Group entries by {project, tool_name, normalized_command}:
- project = cwd path relative to $HOME (e.g. "src/myapp" from "/Users/alice/src/myapp").
  Use the full relative path — never basename alone — to avoid collisions across projects
  that share a directory name.
- tool_name = the tool_name field from the log entry
- normalized_command = for Bash failures, the executable and subcommand (e.g. "npm run e2e",
  not the full argument list); for other tools (Edit, Write, etc.), use tool_name alone

**Flag repeated failures:** Flag any {project, tool_name, normalized_command} with 2 or
more failures. Prioritize patterns with 4+ failures — these are systemic.

**Diagnose each pattern:**
- Bash failures: examine the command for clues:
  - Missing binary → note the install command
  - Wrong path → note the correct path or how to find it
  - Missing env var → note which variable and where to set it
  - Needs sudo → note if elevated privileges are required
  - Needs a running service → note the startup command
- Edit/Write failures: may indicate path or permission issues — note the correct path
  convention or required permissions

---

## Step 3: Present plan

```
Errors improvement plan
════════════════════════════════════════════════════════════════

── Repeated failures ───────────────────────────────────────────
  [project]  CLAUDE.md: pre-flight note for "npm run e2e"
             Failed 4 times. Likely cause: dev server not running.
             Note: "Before npm run e2e, ensure the dev server is running: npm run dev"

  [project]  CLAUDE.md: pre-flight note for "python manage.py test"
             Failed 2 times. Likely cause: missing DJANGO_SETTINGS_MODULE.
             Note: "Set DJANGO_SETTINGS_MODULE=myapp.settings.test before running tests"
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

For each approved CLAUDE.md addition:
- Load the target CLAUDE.md (create with minimal header if it doesn't exist)
- Add under a `## Pre-flight checks` or `## Known issues` heading (create if needed;
  prefer `## Pre-flight checks` for environment/dependency issues)
- Keep notes concise: one line describing the check, one line with the correct command
  or fix
- Do NOT rewrite existing content
- Report: "Updated [path]: added pre-flight note for [command]"

---

## Step 4b: Record audit trail

For each file written or modified, append one line to `~/.slipstream/applied.jsonl`:
```bash
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg cmd "slipstream-errors" \
  --arg action "claude-md-update" \
  --arg target "<absolute path of CLAUDE.md modified>" \
  --arg detail "<e.g. 'Added pre-flight note for npm run e2e'>" \
  '{timestamp: $ts, command: $cmd, action: $action, target: $target, detail: $detail}' \
  >> ~/.slipstream/applied.jsonl
```

## Step 5: Update cursor

Merge into `~/.slipstream/cursors/<project-key>.json` using jq — preserve all other fields:

```json
{"last_errors_review": "<ISO 8601 now>"}
```

If the cursor does not exist, create it with just this field.

---

## Step 6: Report

```
Applied:
  N pre-flight notes added across J CLAUDE.md files
```
