---
name: feedback_settings_relative_paths
description: settings.json additionalDirectories must use relative paths, never absolute with usernames
type: feedback
---

In `.claude/settings.json` `additionalDirectories`, ALWAYS use relative paths. NEVER use absolute paths containing usernames (`C:\Users\<name>\...`).

**Why:** Multiple developers share the same project structure, differing only by username. Absolute paths with usernames break for other devs. The user explicitly demanded this after finding hardcoded `C:\Users\ssv55\` paths scattered across settings files in multiple projects.

**How to apply:**
- From project root: `../iamrich`, `docs/todo`, `front/public`
- Home-relative: `~/.claude`, `~/.claude/memory`, `~/.claude/plans`
- Parent workspace: `../.ssh`, `../.claude/agents`
- NEVER: `C:\Users\ssv55\.claude`, `D:\Data\Documents\Programming\Projects\...`
- When adding a new `additionalDirectories` entry, always compute the relative path from project root or use `~/` for home
- Applies to ALL projects, not just one
