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

**CRITICAL RULES — READ BEFORE PROCEEDING:**
1. Run the pre-built script exactly as shown below. Do not write Python or shell code as a substitute.
2. Read the JSON output directly. Do not pipe it through `python3 -c`, `jq`, or any other command to extract fields — parse it in your head.
3. If the script is not found, stop and tell the user to run `./install.sh` from the slipstream repo.

## Step 1: Run analysis script

If the user provided a time argument (e.g. `7d`, `6h`), pass it as `--since <argument>`. Otherwise omit the flag.

```bash
python3 ~/.claude/hooks/slipstream-analyze-permissions.py [--since DURATION]
```

The script outputs JSON with:
- `total`, `new_since_review`, `earliest`, `latest`
- `patterns` — list of `{tool_name, normalized_pattern, session_count, sessions, count, last_seen, raw_commands, allow_list_candidate}` objects
- `native_tool_candidates` — list of `{bash_cmd, native_tool, session_count}` objects

Show the mini-dashboard:
```
Permissions module
  Total entries:       <total>
  New since review:    <new_since_review>
  Date range:          <earliest> → <latest>
```

If `total` is 0, say:
> No permission data captured yet. Run a few Claude Code sessions and check back.

Stop here — do not proceed to analysis.

---

## Step 2: Analysis

Use the script output directly — no additional data extraction needed.

### A. Allow-list candidates

From `patterns`, select entries where `allow_list_candidate` is true (session_count >= 3).
Cross-project candidates: check `~/.slipstream/projects/*/permissions.jsonl` if you want
to flag patterns appearing across multiple projects.

Score each candidate: session_count × recency_weight, where recency_weight = 1.5 if
last_seen within 30 days, else 1.0. Sort by score descending.

### B. Native tool substitutions

From `native_tool_candidates`, flag each for a CLAUDE.md note:
"Prefer [NativeTool] over [bashcmd] for [purpose]."

Only flag if not already noted in the project's CLAUDE.md.

### C. Script opportunities

From `patterns`, look for:
- Commands longer than 60 characters appearing in 2+ sessions → suggest a script
- 3+ patterns with the same tool appearing in the same sessions (cluster) → suggest a script

For each script opportunity, propose:
- Script name and location (project scripts/, ~/.claude/hooks/, or ~/bin/)
- Script content derived from the distinct commands in the cluster
- A single allow-list entry that covers the script

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
