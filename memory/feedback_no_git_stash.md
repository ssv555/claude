---
name: No git stash — use WIP commits instead
description: Never use git stash when parallel sessions may be editing the same files; use WIP commits instead
type: feedback
originSessionId: 16aef7c4-e334-4de2-abeb-3462511c7707
---
Never use `git stash` in the middle of work when parallel sessions are active (or could be).

**Why:** Session 2f2ea328 did `git stash && bun run i18n:check; git stash pop` — the pop had merge conflicts from parallel session edits, then `git stash drop` permanently destroyed ~40min of work (chief-only gating, SPA nav links). This is unrecoverable.

**How to apply:**
- If you need to temporarily set aside changes: use `git commit -m "WIP"` instead of stash. WIP commits can be `--amend`ed or `reset --soft HEAD~1`ed later.
- NEVER run `git stash drop` without explicit user confirmation ("удалить стеш? да/нет").
- If stash pop produces conflicts — STOP. Do not resolve silently. Show the user and ask how to proceed.
- Before any stash operation: check if other sessions might have touched the same files recently.
