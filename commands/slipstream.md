# /slipstream

Show a dashboard of friction captured for the CURRENT PROJECT and recommend
which focused commands to run.

**CRITICAL RULES — READ BEFORE PROCEEDING:**
1. Run the pre-built script exactly as shown below. Do not write Python or shell code as a substitute.
2. Read the JSON output directly. Do not pipe it through `python3 -c`, `jq`, or any other command to extract fields — parse it in your head.
3. If the script is not found, stop and tell the user to run `./install.sh` from the slipstream repo.

## Step 1: Run dashboard script

```bash
python3 ~/.claude/hooks/slipstream-analyze-dashboard.py
```

The script outputs JSON with:
- `project_key`, `project_cwd`
- `last_review_ts`, `last_review_days` — days since any module was last reviewed (null if never)
- `modules` — one entry per module:
  - `permissions`, `context`, `errors`, `reads` → `{total, new, sessions}`
  - `corrections`, `memory`, `commands` → `{unanalyzed}`

## Step 2: Show dashboard

Print a dashboard using the script output:

```
Slipstream

  Module         New since review   Total    Sessions
  ─────────────────────────────────────────────────────
  Permissions    23                 47       12
  Context         2                  9        4
  Errors          8                 21        6
  Reads          41                112       15
  Corrections     -                  -        3 unanalyzed
  Memory          -                  -        4 unanalyzed
  Commands        -                  -        5 unanalyzed

  Last review: 4 days ago  (or "never" if last_review_days is null)
```

For Corrections, Memory, and Commands: show `-` in New and Total columns;
show the `unanalyzed` count in the Sessions column with the label "unanalyzed".

## Step 3: Recommend commands

Based on the output, print specific recommendations:

- `permissions.new` >= 5        →  suggest /slipstream-permissions
- `context.new` >= 3            →  suggest /slipstream-context
- `errors.new` >= 3             →  suggest /slipstream-errors
- `reads.new` >= 10             →  suggest /slipstream-reads
- `corrections.unanalyzed` >= 2 →  suggest /slipstream-corrections
- `memory.unanalyzed` >= 2      →  suggest /slipstream-memory
- `commands.unanalyzed` >= 3    →  suggest /slipstream-commands

Example output:

```
Recommended:
  /slipstream-permissions   23 new permission events
  /slipstream-corrections    3 sessions not yet analyzed
  /slipstream-memory         4 sessions not yet analyzed
  /slipstream-commands       5 sessions not yet analyzed
```

If nothing meets any threshold, say:

> No modules have accumulated enough data for a review yet. Check back after a few more sessions.
