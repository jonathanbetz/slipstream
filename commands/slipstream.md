# /slipstream

Show a dashboard of friction captured across all Claude Code sessions and recommend
which focused commands to run.

## Step 1: Read logs

Read these files from ~/.slipstream/:
- permissions.jsonl
- compactions.jsonl
- errors.jsonl
- reads.jsonl
- corrections-state.json (for analyzed_session_ids; default [])
- memory-state.json (for analyzed_session_ids for the memory module; default [])
- commands-state.json (for analyzed_session_ids for the commands module; default [])
- .cursor.json (for last-review state and per-module line counts)

Count total lines in each jsonl file. Count distinct session_ids in each.

Count unanalyzed sessions per transcript-scanning module by subtracting each module's
analyzed_session_ids from the total list of *.jsonl files under ~/.claude/projects/:
- corrections-state.json → unanalyzed sessions for /slipstream-corrections
- memory-state.json     → unanalyzed sessions for /slipstream-memory
- commands-state.json   → unanalyzed sessions for /slipstream-commands

"New since review" for each log module = current line count minus the line count stored
in .cursor.json for that module (permissions_line_count, compactions_line_count,
errors_line_count, reads_line_count). If no .cursor.json exists, treat stored counts as 0.

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
