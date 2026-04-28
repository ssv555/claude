---
name: Brevity is default — short but clear
description: User repeatedly demands shorter responses; default is the minimum that fully conveys the answer. Long form only on explicit request.
type: feedback
originSessionId: ae90c689-d3ba-4070-bdb6-9abf57fb2e8f
---
Default response = the shortest text that the user can act on. NOT the shortest text period — short does NOT mean cryptic. Cut the explanations, options, alternatives, repetition. Keep what the user needs to decide / do.

**Why:** user has reminded me dozens of times; multi-paragraph answers, long bullet lists, and repeated context dumps make the conversation unusable. Verbosity is the #1 friction point in this collaboration.

**How to apply:**
- Default: 1 sentence to a few short bullets. Tables only when comparing many rows.
- Yes/no question → "yes" / "no" + 1 short reason if not obvious.
- Status update → 1 sentence.
- Plan / tradeoff list → only when user asks for "распиши", "подробно", "вариант", "план", "сравни", or similar.
- After tool calls: 1 sentence what changed + 1 sentence next ask. No "summary of what I did", no "и теперь сделаю X", no closing pleasantries.
- If user asks a clarifying question, ANSWER it in one line — don't restart the whole context.
- Never repeat in chat what's already visible in a tool result the user can see.

This OVERLAPS with the global CLAUDE.md "Response Style — UNIVERSAL" rule but is recorded here because the user has called it out as recurring violation specifically in this project.
