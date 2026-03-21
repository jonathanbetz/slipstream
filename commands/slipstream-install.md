# /slipstream-install

Install Slipstream friction tracking for the current project. Work through the steps below.

---

## Step 1: Verify global hooks are active

Read `~/.claude/settings.json`. Confirm that all six Slipstream hooks are present:

- `PermissionRequest` → `~/.claude/hooks/slipstream-capture-permission.sh`
- `PreCompact` → `~/.claude/hooks/slipstream-capture-compaction.sh`
- `PostToolUseFailure` → `~/.claude/hooks/slipstream-capture-errors.sh`
- `PostToolUse` (matcher: `Read|Glob`) → `~/.claude/hooks/slipstream-capture-reads.sh`
- `Stop` → `~/.claude/hooks/slipstream-check-triggers.sh`
- `SessionStart` → `~/.claude/hooks/slipstream-check-triggers.sh`

If any hooks are missing, tell the user:

> One or more Slipstream hooks are missing from ~/.claude/settings.json. Please re-run install.sh from the Slipstream repo:
>
> ```
> cd /path/to/slipstream
> ./install.sh
> ```
>
> Then run /slipstream-install again.

Stop if hooks are missing.

---

## Step 2: Locate the project root

The project root is the current working directory (`cwd`). Find or create `.claude/settings.local.json` inside the project root. Prefer `.claude/settings.local.json` over `.claude/settings.json` for machine-specific configuration — settings.local.json should not be committed to version control.

Create the `.claude/` directory if it doesn't exist.

If `.claude/settings.local.json` doesn't exist, create it with:
```json
{}
```

---

## Step 3: Add the per-project Stop hook

Load `.claude/settings.local.json`. Check whether a `Stop` hook pointing to `~/.claude/hooks/slipstream-check-triggers.sh` is already present.

If not present, add it:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/slipstream-check-triggers.sh",
            "timeout": 3000
          }
        ]
      }
    ]
  }
}
```

Use `jq` to merge this entry idempotently — do not overwrite existing hooks, do not add duplicates.

If the file already has a `Stop` hook with this command, skip silently.

---

## Step 4: Check .gitignore

Check whether `.gitignore` exists at the project root. Look for these two entries:
- `.claude/settings.local.json`
- `.claude/permission-log.jsonl`

If either is missing from `.gitignore`, show the user exactly what to add:

> Consider adding these lines to your `.gitignore` to avoid committing machine-specific config or local logs:
>
> ```
> .claude/settings.local.json
> .claude/permission-log.jsonl
> ```
>
> (Not auto-added — update .gitignore if you want these excluded.)

Do NOT automatically edit `.gitignore`. Just surface the suggestion.

---

## Step 5: Print confirmation

```
Slipstream installed for [project name]:
  ✓ Global capture hooks active (6 hooks in ~/.claude/settings.json)
  ✓ Per-project Stop trigger added to .claude/settings.local.json

Friction events will appear in ~/.slipstream/ as you work.
Run /slipstream at any time to analyze and reduce friction.
```

Where `[project name]` is the last meaningful component of the project root path.
