---
name: Commit after each approved step in multi-step sessions
description: In multi-step plans (M1, M2, M3...) output a git commit command after each completed step for rollback safety
type: feedback
originSessionId: 92058ac1-2386-4e7b-9d20-62656b5d7871
---
In sessions broken into sequential approved atoms (e.g. M1 → M2 → M3), output a git commit command after EACH completed step — don't batch multiple steps into one commit.

**Why:** User on 2026-04-19 during task 03 docs prep: «Может, после каждого шага будем делать комит? На всякий случай.» Rationale: each step is an independent, approved unit; if a later step goes wrong, rollback should revert only that step, not the whole chain.

**How to apply:**
- After finishing an approved step and showing the diff, output ONE git command per CLAUDE.md format:
  `cd /d <project_path> && git add <specific-files> && git commit -m "msg" && git pull --rebase && git push`
- Use specific file paths in `git add`, not `-A`, when the working tree has other unrelated dirty files (normal state of this repo — lots of ongoing WIP).
- NEVER run `git commit` / `git push` yourself — user runs manually (global rule).
- Wait for user to confirm push succeeded before starting the next step.
- Commit message: short, factual, project convention (prefix like `docs:`, `refactor:`, `fix:`, etc.).
