---
name: feedback_todo_checkbox_format
description: Task completion markers must be at the START of the line, never in the middle or end
type: feedback
---

Task completion markers (`[x]`, `[ ]`, `✅`, `⬜`) must always be at the START of the line, never in the middle or end of the body.

**Why:** User explicitly corrected this multiple times — putting status markers mid-line (like `~~text~~ — ✅ DONE` or `| ✅ DONE |` in tables) is unreadable and unprofessional. Tables with status columns are also bad — use checkbox lists instead.

**How to apply:**
- Use `- [x] Task description (date)` for done items
- Use `- [ ] Task description` for pending items
- Never use `~~strikethrough~~` with status at the end
- Never use table columns for status — convert to checkbox lists
- This applies to all markdown files: docs, plans, TODO lists, audit reports
