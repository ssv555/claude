---
name: FIX ALL ERRORS — NO EXCUSES, NO EXCEPTIONS
description: ALL typecheck/lint/build errors — fix regardless of origin. Small = fix silently. Large = ask first. Never say "not my code".
type: feedback
---

ALL typecheck/lint/build errors — fix regardless of origin.
Never classify errors as "not my changes", "pre-existing", or any variation.

**Small fix** (< ~20 lines, no architectural impact) → fix silently, no commentary about origin.
**Large fix** (refactor, new dependency, architectural change) → describe the problem and proposed fix, ask before doing.

**Why:** Rule violated repeatedly because global CLAUDE.md "ASK BEFORE EXTRA CHANGES" had a narrow exception ("caused BY your own changes") that contradicted this rule. Fixed 2026-04-07 — exception now matches: all errors, regardless of origin.

**How to apply:**
1. Run typecheck / lint / build / tests
2. See an error? → Evaluate size. Small → fix. Large → ask.
3. NEVER comment about whether the error is "mine" or "not mine".
