# /slipstream-permissions

Analyze permission friction, propose allow-list entries, native tool substitutions, and
reusable scripts. Present a ranked plan, wait for approval, then apply.

---

## Step 0: Determine current project

Before reading any data:
1. Current project path = the working directory where Claude Code is open (`pwd`).
2. Project key = that path with every `/` replaced by `-`
   (e.g. `/Users/alice/src/myapp` → `-Users-alice-src-myapp`).
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).
4. Project sessions directory = `~/.claude/projects/<project-key>/`.

All analysis below is SCOPED TO THE CURRENT PROJECT only.

## Step 1: Mini-dashboard

Load `~/.slipstream/projects/<project-key>/permissions.jsonl`. Load the per-project cursor.

Show:
- Total entries (line count for this project)
- New since last review: count of entries with `.timestamp` > `last_permissions_review`
  in per-project cursor (if no cursor, all entries are "new")
- Date range (earliest and latest timestamp among entries)

If the file is empty or missing, say:

> No permission data captured yet. Run a few Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

Run all three analyses before presenting anything.

### A. Allow-list candidates

Group entries by {project, normalized_pattern}:
- project = cwd path relative to $HOME (e.g. "src/myapp" from "/Users/alice/src/myapp").
  Use the full relative path — never basename alone — to avoid collisions across projects
  that share a directory name.
- normalized_pattern = normalize Bash commands by stripping variable arguments:
  - Replace quoted strings, file paths, and version numbers with *
  - If a command varies across sessions in its arguments, append * to the base command
  - Example: `npm install lodash` and `npm install react` → `npm install *`
  - Example: `git commit -m "fix bug"` → `git commit *`
  - Keep commands that are always identical as-is

Flag a {project, normalized_pattern} as an allow-list candidate if ALL are true:
- Appears in 3 or more distinct sessions (session_count >= 3)
- Not already present in ~/.claude/settings.json or the project's .claude/settings.json allow list
- The command looks safe (not rm -rf, not destructive system commands)

Cross-project candidates: if the same normalized pattern appears in 2+ distinct projects
with session_count >= 2 each, flag it as a global ~/.claude/settings.json candidate.
Iterate over `~/.slipstream/projects/*/permissions.jsonl` for cross-project analysis.

Score each candidate: session_count × recency_weight, where recency_weight = 1.5 if last
seen within 30 days, else 1.0. Sort candidates by score descending.

### B. Native tool substitutions

Look for Bash commands that Claude Code has a native equivalent for:
- grep / grep -r / rg  →  Grep tool
- find / ls            →  Glob tool
- cat / head / tail    →  Read tool
- echo > file / tee    →  Write tool
- sed -i               →  Edit tool

If a native-substitute command appears in 2+ sessions in the same project, flag it for a
CLAUDE.md note: "Prefer [NativeTool] over [bashcmd] for [purpose]."

Only flag if not already noted in that project's CLAUDE.md.

### C. Script opportunities

Look for:
- Session clusters: 3+ Bash permission requests within 15 minutes in the same session,
  where the cluster pattern repeats across 2+ sessions → suggest a reusable script
- Repeated complex commands: same command in 4+ sessions, OR any command longer than 60
  characters in 2+ sessions → suggest a script
- Cross-project duplicates: same cluster pattern in 2+ projects → suggest a ~/bin/ script

For each script opportunity, propose:
- Script name and location (project scripts/, ~/.claude/hooks/, or ~/bin/)
- Script content derived from the distinct commands in the cluster
- A single allow-list entry that covers the script, replacing the individual entries
- Whether a slash command wrapper makes sense

---

## Step 3: Present plan

Present a ranked improvement plan ordered by friction sessions eliminated:

```
Permissions improvement plan
════════════════════════════════════════════════════════════════

── Allow-list candidates ───────────────────────────────────────
  [project]  Allow: Bash(npm test)            8 sessions
  [global]   Allow: Bash(gh run list *)       5 sessions, 3 projects

── Native tool substitutions ───────────────────────────────────
  [project]  CLAUDE.md: prefer Grep over grep   4 sessions

── Script opportunities ────────────────────────────────────────
  [project]  New script: scripts/deploy.sh      replaces 4-cmd cluster, 6 sessions
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
cp ~/.claude/settings.json ~/.slipstream/backups/settings.json.${TS}.bak 2>/dev/null || true
# For each project settings.json being modified, back it up similarly.
```
Report the backup path so the user knows where to find it.

Work through approved items in this order:

**Scripts first:**
- Write the script to the proposed location
- Run `chmod +x` on it
- If a slash command wrapper was proposed, create it in ~/.claude/commands/ or .claude/commands/
- Report: "Created [path]"

**Allow-list additions:**
- Load the target settings file (~/.claude/settings.json or [project]/.claude/settings.json)
- Add each approved command to the permissions.allow array
- If the file lacks a permissions key, add it; preserve all existing structure
- Idempotent: skip if the entry is already present
- Report: "Updated [path]: added N allow entries"

**CLAUDE.md updates (tool preference notes):**
- Load the target CLAUDE.md (create with minimal header if missing)
- Add under a `## Tool preferences` heading (create if needed)
- Do NOT rewrite existing content
- Report: "Updated [path]: added Tool preferences note"

---

## Step 4b: Record audit trail

For each file written or modified, append one line to `~/.slipstream/applied.jsonl`:
```bash
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg cmd "slipstream-permissions" \
  --arg action "<allow-list-add|claude-md-update|script-created>" \
  --arg target "<absolute path of file modified>" \
  --arg detail "<brief description of change>" \
  '{timestamp: $ts, command: $cmd, action: $action, target: $target, detail: $detail}' \
  >> ~/.slipstream/applied.jsonl
```
Append one entry per change. Never read or rewrite the file — append only.

## Step 5: Update cursor

Merge into the per-project cursor `~/.slipstream/cursors/<project-key>.json` using jq —
preserve all other fields:

```json
{"last_permissions_review": "<ISO 8601 now>"}
```

Example jq command:
```bash
CURSOR="$HOME/.slipstream/cursors/<project-key>.json"
mkdir -p "$(dirname "$CURSOR")"
jq -s '.[0] * .[1]' "$CURSOR" - <<< \
  '{"last_permissions_review": "2026-03-21T14:30:00Z"}' \
  > /tmp/cursor.tmp && mv /tmp/cursor.tmp "$CURSOR"
```

If the cursor does not exist, create it with just this field.

---

## Step 6: Report

```
Applied:
  N allow entries added across M projects
  K scripts created
  J CLAUDE.md files updated
```
