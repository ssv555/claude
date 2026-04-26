---
name: tools-tokens
description: KTU analysis — developer contribution & code complexity report from git history. Per-project report and timestamps stored at `{project_root}/.claude/tokens-report.md`.
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
model: opus
---

# Tokens — KTU Analysis (global)

This is a global skill. The actual logic lives in `logic.md` next to this file.

## Execution

1. **Resolve logic file path** — same directory as this `SKILL.md`:
   ```
   LOGIC_FILE = {skill_dir}/logic.md
   ```
   Where `{skill_dir}` is the directory containing the `SKILL.md` you are currently executing (do NOT hardcode `~/.claude/...` — it must work from any global-skill installation path).

2. **Resolve project root** — current working directory of the conversation (typically the project root). All project-relative paths in `logic.md` (`REPORT_FILE`, optional config) are resolved against this.

3. **Optional per-project override** — before running:
   - Check if `{project_root}/.claude/tokens-config.md` exists.
   - If yes — read it. If it contains an `## Author Alias Map` section in the same table format as `logic.md`, USE THAT MAP INSTEAD of the default in `logic.md`. Anything else from the override file is ignored unless `logic.md` explicitly says otherwise.
   - If no — use defaults from `logic.md` (the VDole-era default has `ssv555` and `Kirill`; that is fine for any project where those are still the active developers).

4. **Validate**:
   - The `logic.md` file exists and is non-empty → otherwise output `ERROR: Logic file not found at {path}. Reinstall the skill.` and STOP.

5. **Execute** — Read `logic.md` and follow ALL its instructions strictly in order. The logic file is authoritative on every step (fetching commits, weighting, COCOMO, report writing).

## Per-project file layout (created by this skill on first run)

```
{project_root}/
  .claude/
    tokens-report.md      ← cumulative report + LAST_ANALYSIS_DATE marker
    tokens-config.md      ← OPTIONAL: per-project author alias overrides
```

`{project_root}/.claude/` is the standard Claude Code project-config folder; the skill writes its report there so each project keeps its own history and timestamps. `tokens-report.md` is gitignored on most projects (default `.claude/*` rule with `!.claude/user.conf` whitelist) — that is the intended behavior.
