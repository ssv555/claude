---
name: Receive → analyze → approve before coding
description: User's process: first accept all inputs, then analyze, only start work after explicit approval
type: feedback
originSessionId: 92058ac1-2386-4e7b-9d20-62656b5d7871
---
Before starting any non-trivial task: first accept ALL input files/answers from the user, then analyze them against the real codebase, then WAIT for explicit approval ("делай", "ок", "поехали") before touching code.

**Why:** User explicitly stated this on 2026-04-19 at the start of task 03 (agent profiles): «Прежде чем приступать к разработке, нужно сначала принять от меня все файлы, а потом проанализировать, а потом только приступать. И то, если я дам добро.» Premature starts waste time and produce rework.

**How to apply:**
- Collect all user-provided docs/specs/answers first.
- Produce a discrepancy/analysis report (what's in spec vs what's in code; open questions).
- Propose a small, numbered list of concrete next actions.
- STOP and wait for explicit approval — do not begin editing code even after answering the last question.
- Combines with WAIT FOR EXPLICIT APPROVAL: any text that isn't a clear "yes" counts as additional input.
