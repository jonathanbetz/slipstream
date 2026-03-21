# /slipstream

Show a dashboard of friction captured for the CURRENT PROJECT and recommend
which focused commands to run.

## Step 0: Determine current project

Before reading any data:
1. The current project path = the working directory where Claude Code is open (run `pwd` if needed).
2. Project key = that path with every `/` replaced by `-`
   (e.g. `/Users/alice/src/myapp` → `-Users-alice-src-myapp`).
3. Per-project cursor = `~/.slipstream/cursors/<project-key>.json` (default `{}` if missing).
4. Project sessions directory = `~/.claude/projects/<project-key>/`.

All data in the steps below is SCOPED TO THE CURRENT PROJECT.

## Step 1: Read logs

Read these files from ~/.slipstream/:
- permissions.jsonl  — filter to entries where `.cwd` starts with the current project path
- compactions.jsonl  — same filter
- errors.jsonl       — same filter
- reads.jsonl        — same filter
- corrections-state.json (for analyzed_session_ids; default [])
- memory-state.json (for analyzed_session_ids for the memory module; default [])
- commands-state.json (for analyzed_session_ids for the commands module; default [])
- ~/.slipstream/cursors/<project-key>.json (per-project last-review timestamps)

Count filtered entries in each jsonl file. Count distinct session_ids among filtered entries.

Count unanalyzed sessions per transcript-scanning module using ONLY sessions under
`~/.claude/projects/<project-key>/`:
- corrections-state.json → unanalyzed sessions for /slipstream-corrections
- memory-state.json     → unanalyzed sessions for /slipstream-memory
- commands-state.json   → unanalyzed sessions for /slipstream-commands

"New since review" = count of filtered entries (matching project cwd) with `.timestamp`
greater than the corresponding `last_*_review` timestamp in the per-project cursor.
If no cursor exists, all filtered entries are "new".

## Step 2: Show dashboard

Print a dashboard like this:

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

  Last review: 4 days ago  (or "never" if last_review_timestamp is absent)
```

"New since review" for Corrections, Memory, and Commands = count of unanalyzed sessions
(not a line count). Show "-" for these modules in the Total and Sessions columns; show
the unanalyzed count in the Sessions column with the label "unanalyzed".

"Last review" is computed from last_review_timestamp in .cursor.json. If no such key
exists, show "never".

## Step 3: Recommend commands

Based on the counts above, print specific recommendations:

- Permissions new >= 5        →  suggest /slipstream-permissions
- Context (compactions) new >= 3  →  suggest /slipstream-context
- Errors new >= 3             →  suggest /slipstream-errors
- Reads new >= 10             →  suggest /slipstream-reads
- Corrections unanalyzed >= 2 →  suggest /slipstream-corrections
- Memory unanalyzed >= 2      →  suggest /slipstream-memory
- Commands unanalyzed >= 3    →  suggest /slipstream-commands

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
