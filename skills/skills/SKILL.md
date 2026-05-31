---
name: skills
description: List all available skills (global and local) with clickable paths
model: sonnet
fork: true
allowed-tools: Glob, Read, Bash
---

List all skills (global + local) as a markdown table with clickable file paths.

## Execution

1. Use Glob (`**/*.md`) to find all SKILL.md / skill.md files under `~/.claude/skills/` (global) and `.claude/skills/` in the current project directory (local). Ignore README.md.
2. For each found file, extract the skill name from the parent directory name (e.g. `git-push/SKILL.md` → `/git-push`).
3. Resolve the REAL path of global skills directory:
   - Run: `powershell.exe -Command "(Get-Item '$env:USERPROFILE\.claude\skills').Target"`
   - This gives the real path (e.g. `D:\Data\Documents\Programming\Projects\AI\Claude\skills`)
   - Then compute the relative path from the current project root to that real path using `../` segments
4. Output a numbered markdown table with columns: `#`, `Скилл`, `Путь`.
   - `Скилл` = `/<directory-name>`
   - ALL paths (global and local) MUST be clickable relative markdown links using forward slashes
   - **Локальные** example: `[.claude/skills/pre-deploy-check-build/SKILL.md](.claude/skills/pre-deploy-check-build/SKILL.md)`
   - **Глобальные** example: `[../../AI/Claude/skills/git-push/SKILL.md](../../AI/Claude/skills/git-push/SKILL.md)`
5. Group: first **Глобальные**, then **Локальные** (skip section if empty).
6. Sort alphabetically within each section.

## Computing relative path

Given:
- Project root (from pwd): e.g. `D:\Data\Documents\Programming\Projects\WEB\ServerBun`
- Global skills real path: e.g. `D:\Data\Documents\Programming\Projects\AI\Claude\skills`

Count how many directories up from project root to the common ancestor, then append the remaining path down. Use forward slashes only.

## Rules

- Output ONLY the table — no greetings, no commentary, no questions.
- ALL paths MUST be clickable relative markdown links with forward slashes.
- Include symlinked skills — resolve and show target path.
- Sequential numbering across both sections (global 1-N, local N+1...).
- If resolving the symlink fails, fall back to absolute path in backticks.
