# Codex — Engineering Principles

> Lines marked 👤 are for user reference only — AI must NOT read the linked file. The rule names alone are sufficient for AI to apply them.

- SOLID 👤 [description](./codex_description.md#solid)
- DRY, Decomposition, Separation of Concerns 👤 [description](./codex_description.md#dry--decomposition)
- Composition over inheritance, max depth 2 👤 [description](./codex_description.md#oop--inheritance)
- KISS, YAGNI, Boy Scout Rule, Least Surprise 👤 [description](./codex_description.md#core-principles)
- Guard clauses, naming conventions, CQS, Law of Demeter, no magic values 👤 [description](./codex_description.md#clean-code)
- Immutability, pure functions, pipe/compose 👤 [description](./codex_description.md#functional-patterns)
- Edge cases (null/empty/boundary), off-by-one, type coercions, control flow completeness 👤 [description](./codex_description.md#correctness)
- Race conditions, transactions for multi-step writes, TOCTOU, partial failure recovery 👤 [description](./codex_description.md#concurrency--data-integrity)
- No redundant/derivable state, no stringly-typed code, no leaky abstractions, comments explain "why" 👤 [description](./codex_description.md#code-hygiene)
- Traceable errors, structured logging, fail fast 👤 [description](./codex_description.md#debug--error-handling)
- OWASP Top 10, input validation, least privilege, never trust client, no exposed secrets 👤 [description](./codex_description.md#security-by-design)
- Logic preservation: refactoring and review must never change observable behavior 👤 [description](./codex_description.md#logic-preservation)
- Review depth proportional to semantic complexity, not line count 👤 [description](./codex_description.md#adaptive-review-depth)
- Testing pyramid, AAA, test behavior not implementation 👤 [description](./codex_description.md#testing)
- Lazy loading, pagination, N+1 prevention, no blocking in async, sequential→parallel, bounded data structures 👤 [description](./codex_description.md#performance)
