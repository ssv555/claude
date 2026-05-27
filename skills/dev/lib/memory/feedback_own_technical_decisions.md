---
name: Make own technical decisions for code quality
description: For implementation-time technical choices, decide yourself based on quality and future stability — don't arbitrate with user
type: feedback
originSessionId: ddd0fc55-b8c5-4ce6-a092-7cc46c1dac40
---
When implementing an approved task, make architectural/technical decisions independently based on code quality and future stability. Don't ask the user to arbitrate small technical choices (which endpoint pattern, where helpers live, schema details, caching strategy, data-flow splits, etc.) — that's Claude's job.

**Why:** User got explicitly angry ("ПРИНИМАЙ РЕШЕНИЯ САМ в соответствии с качеством и стабильностью кода на БУДУЩЕЕ!!!") after I kept asking yes/no on internal arch choices (public-endpoint split, init-route auth) during UI-gradient admin implementation. Prior behavior: every time I hit a branch I paused to ask. Problem: that's not collaboration — that's offloading decisions. The user wanted me to think through tradeoffs and pick the cleanest/most stable option, not re-litigate every call.

**How to apply:**

1. **Decide and move** on technical calls where the user has no strong stake: endpoint naming, file layout, caching key naming, error format, zod vs. ajv, library micro-choice, whether to split a module, naming conventions, type shapes. Pick the option that future-proofs the code — smaller surface area, less coupling, clearer boundaries, easier to delete later. Explain briefly in chat what I chose and why, then proceed.

2. **Still ask** when a decision materially affects:
   - Scope (adds/removes a non-trivial feature)
   - UX or user-visible behavior
   - Cost / time / deploy risk
   - Contradicts a prior explicit instruction
   - Security posture (auth boundaries, data exposure)
   - Destructive or hard-to-reverse actions

3. **Not in conflict with `feedback_receive_analyze_approve`**: that rule is about waiting for explicit approval on the TASK itself before coding. This rule is about not micro-asking DURING approved implementation.

4. **Not in conflict with `THINK BEFORE CODING` in global CLAUDE.md**: that rule says "surface genuine ambiguity in the REQUEST". This rule says don't manufacture ambiguity for internal tech choices — those aren't ambiguity, those are engineering decisions.
