# /slipstream-errors

Analyze repeated tool failures and propose pre-flight notes that prevent them. Present a
plan, wait for approval, then apply.

---

## Step 1: Mini-dashboard

Load ~/.slipstream/errors.jsonl. Load ~/.slipstream/.cursor.json.

Show:
- Total entries (line count)
- New since last review (current count minus errors_line_count in .cursor.json; 0 if missing)
- Distinct tools involved (distinct tool_name values)
- Distinct projects (distinct meaningful directory names from the cwd field)

If the file is empty or missing, say:

> No error data captured yet. Tool failures are logged when a hook or tool call exits
> non-zero. Run a few Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

**Group by pattern:** Group entries by {project, tool_name, normalized_command}:
- project = meaningful directory name from cwd (last non-trivial path component)
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

For each approved CLAUDE.md addition:
- Load the target CLAUDE.md (create with minimal header if it doesn't exist)
- Add under a `## Pre-flight checks` or `## Known issues` heading (create if needed;
  prefer `## Pre-flight checks` for environment/dependency issues)
- Keep notes concise: one line describing the check, one line with the correct command
  or fix
- Do NOT rewrite existing content
- Report: "Updated [path]: added pre-flight note for [command]"

---

## Step 5: Update cursor

Merge into ~/.slipstream/.cursor.json using jq — preserve all other fields:

```json
{"errors_line_count": <current wc -l of errors.jsonl>, "last_errors_review": "<ISO 8601 now>"}
```

If .cursor.json does not exist, create it with just these two fields.

---

## Step 6: Report

```
Applied:
  N pre-flight notes added across J CLAUDE.md files
```
