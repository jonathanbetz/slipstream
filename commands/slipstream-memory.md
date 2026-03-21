# /slipstream-memory

Analyze Claude Code session transcripts to find user-level facts that should be persisted
in Claude's memory system but aren't yet. Propose additions to MEMORY.md and individual
memory files.

## State tracking

Uses `~/.slipstream/memory-state.json` with format `{"analyzed_session_ids": [...]}`.
Cumulative — never overwrite, always merge newly analyzed IDs.

## Mini-dashboard

1. List all `*.jsonl` files under `~/.claude/projects/`.
2. Read `analyzed_session_ids` from `~/.slipstream/memory-state.json` (default `[]`).
3. Compute unanalyzed count = total sessions minus analyzed count.
4. Print:
   ```
   Memory module
     Total sessions:      N
     Already analyzed:    M
     Unanalyzed:          K
   ```
5. If unanalyzed < 2, say: "Not enough new sessions to analyze yet. Check back after a
   few more sessions." and stop.

## Step 1: Find the memory system

Look for MEMORY.md in these locations, in order:
1. `~/.claude/memory/MEMORY.md`
2. `.claude/memory/MEMORY.md` in the current working directory
3. Any directory named `memory/` under `~/.claude/projects/`

If found, read MEMORY.md to understand what is already recorded and avoid duplicates.
Also read any existing memory files it references.

If not found, note that no memory system exists yet — proposals will include creating it.

## Step 2: Read unanalyzed transcripts

For each unanalyzed session transcript (a `*.jsonl` file not in `analyzed_session_ids`),
read it line by line. Each line is a JSON object with at least `role` and `content` fields.

Look for **user-level signals** — facts about the person, not the project:

- **Role/identity signals**: user stating their job, expertise, or background
  ("I'm a VC", "I'm the founder", "I've been writing Go for 10 years")
- **Preference signals**: how the user likes Claude to work
  ("keep responses short", "don't add comments", "always show the plan first")
- **Knowledge signals**: what the user knows well vs. what they're new to
  ("I know Python but this is my first TypeScript project")
- **Correction signals**: user correcting Claude's assumption about who they are or how
  they like to work (NOT project-specific corrections — those belong in the corrections
  module)
- **Context-setting patterns**: user providing the same background at the start of
  multiple sessions ("as someone who runs a VC fund...")
- **Feedback patterns**: user repeatedly approving or rejecting the same types of
  Claude behavior

## Step 2b: Distinguish user-level from project-level

Only flag facts that:
- Describe the USER (their role, expertise, preferences, working style)
- Would be useful across ALL projects, not just one
- Are not already captured in existing memory files

Skip facts that:
- Describe the codebase, architecture, or conventions (those belong in CLAUDE.md)
- Are one-time corrections about a specific task
- Are too specific to one project

## Step 3: Cluster findings

Group by memory type:
- `user` — role, background, expertise
- `feedback` — preferences about how Claude should behave
- `project` — cross-cutting project context (only if genuinely cross-project)
- `reference` — pointers to external systems the user references repeatedly

Deduplicate: if a fact is already in an existing memory file, skip it.

## Step 4: Present plan

Present a plan and **wait for user approval before writing anything**:

```
Memory improvement plan

  New memory entries (N):

  [user] user_role.md
    "User is a venture capitalist focused on B2B SaaS. Has technical background."
    Evidence: stated in 4 sessions across 3 projects

  [feedback] feedback_response_style.md
    "User prefers terse responses. No trailing summaries."
    Evidence: corrected verbose responses in 3 sessions

  [feedback] feedback_testing.md (UPDATE — add to existing)
    "User prefers integration tests over unit test mocks."
    Evidence: mentioned in 2 sessions
```

If no new facts were found, say so and stop.

## Step 5: Apply

For each approved entry:

1. Determine the memory directory (the directory containing MEMORY.md, or
   `~/.claude/memory/` if no memory system exists yet).

2. Determine file path: `<memory-dir>/<type>_<slug>.md`

3. Write with frontmatter format:
   ```markdown
   ---
   name: <descriptive name>
   description: <one-line description>
   type: <user|feedback|project|reference>
   ---

   <memory content>
   ```

4. Update MEMORY.md to add a pointer line for any new file:
   `- [filename.md](filename.md) — <one-line description>`

5. For updates to existing files: append the new fact with a brief context note.

## Step 6: Update state

After applying all approved entries:

1. Read `~/.slipstream/memory-state.json` (or start with `{"analyzed_session_ids": []}`
   if it doesn't exist).
2. Merge the newly analyzed session IDs into `analyzed_session_ids` — append, never
   replace.
3. Write the merged object back to `~/.slipstream/memory-state.json`.
4. Read `~/.slipstream/.cursor.json` (or `{}` if missing). Merge in:
   `{"last_memory_review": "<ISO 8601 timestamp of now>"}`. Write it back.

## Report

Print a summary:
```
Done.
  N memory files created
  M memory files updated
  MEMORY.md refreshed
```
