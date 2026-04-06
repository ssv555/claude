# Codex — Full Descriptions (for user reference only)

> This file contains detailed explanations of engineering principles listed in `codex.md`.
> AI agents should NOT read this file — it exists for human reference only.

---

## SOLID

- **S** — Single Responsibility: one module/class/function = one reason to change
- **O** — Open/Closed: extend via composition, not modification of existing code
- **L** — Liskov Substitution: subtypes must be substitutable for their base types
- **I** — Interface Segregation: small focused interfaces over fat ones
- **D** — Dependency Inversion: depend on abstractions, not concrete implementations

## DRY & Decomposition

- **DRY**: Do not repeat logic. Extract shared code into reusable modules. But avoid premature abstraction — 3 occurrences before extracting
- **Decomposition**: Break complex logic into small, testable, single-purpose functions. Max function length ~30 lines. If a function needs a comment explaining "what" — it should be a separate function with a descriptive name
- **Separation of concerns**: DB logic in services/repositories, validation in schemas, routing in routes, UI in components

## OOP & Inheritance

- Prefer **composition over inheritance** — avoid deep class hierarchies
- Inheritance max depth: 2 levels. If deeper — refactor to composition
- Use **interfaces** for contracts, **abstract classes** only when sharing implementation

## Core Principles

- **KISS** — Keep It Simple. Simple solution > clever solution. If it needs a long explanation — simplify
- **YAGNI** — You Ain't Gonna Need It. Don't write code for hypothetical future requirements
- **Boy Scout Rule** — Leave code cleaner than you found it. Small improvements on every touch
- **Principle of Least Surprise** — Code should behave as the reader expects. No hidden side effects, no surprising defaults

## Clean Code

- **Guard Clauses / Early Return** — exit early instead of deep nesting. Max nesting: 3 levels
- **Naming** — variable answers "what", function answers "what it does", boolean starts with `is`/`has`/`can`/`should`
- **Command-Query Separation** — function either performs an action OR returns data, never both
- **Law of Demeter** — don't chain: `user.address.city.name` → bad. Access through direct dependency only
- **No Magic Numbers/Strings** — all literals into named constants

## Functional Patterns

- **Immutability** — prefer `const`, use spread/destructuring instead of mutation, avoid `let` where possible
- **Pure Functions** — same input → same output, no side effects. Isolate side effects to the edges
- **Pipe/Compose** — chain transformations instead of nested calls. Use async/await, Promise.all for parallel work

## Correctness

- **Edge cases** — always handle null, undefined, empty string, empty array, zero, boundary values. Never assume "happy path only"
- **Off-by-one** — verify loop bounds, slice/substring indices, array access. Fence-post errors are the most common bug class
- **Type coercions** — use strict equality (`===`), explicit parsing (`Number()`, `parseInt` with radix), no implicit truthy/falsy for non-booleans
- **Control flow completeness** — every `switch` has a `default`, every `if/else` chain handles the "else", every `try` has meaningful `catch`, every early return is intentional

## Concurrency & Data Integrity

- **Race conditions** — shared mutable state accessed from multiple async flows must be protected (locks, queues, atomic ops)
- **Transactions** — multi-step writes that must succeed or fail together → wrap in a DB transaction
- **TOCTOU** (Time-of-Check-Time-of-Use) — never check a condition then act on it later without re-validation. The state may have changed between check and use
- **Partial failure recovery** — if step 3 of 5 fails, what happens to steps 1–2? Ensure rollback or idempotent retry. Never leave inconsistent state

## Code Hygiene

- **No redundant/derivable state** — if a value can be computed from existing state, compute it. Don't store copies that can drift out of sync
- **No stringly-typed code** — use constants, enums, or branded types instead of raw string literals for domain values (status codes, action types, roles)
- **No leaky abstractions** — a module's internal details must not leak to its consumers. If callers need to know implementation details to use it correctly, the abstraction is broken
- **Comments explain "why", not "what"** — code should be self-explanatory for "what". Comments are for non-obvious intent, workarounds, and business reasons
- **No parameter sprawl** — if a function takes >3–4 params, group into an options object. If functions differ only in 1–2 params, consolidate instead of copy-pasting

## Debug & Error Handling

- Every error must be **traceable**: include context (userId, entityId, action) in error logs
- Use structured logging with context objects, not string concatenation
- Never swallow errors silently. Fail fast, fail loud in development
- Production: graceful degradation with user-friendly messages, detailed server-side logs

## Security by Design

- **OWASP Top 10** awareness: XSS, SQL injection, CSRF, broken auth — consider on every endpoint
- **Input validation at boundaries** — validate all API inputs, sanitize before output
- **Least Privilege** — minimum permissions by default. Users get access explicitly, not implicitly
- **Never trust client data** — validate and sanitize everything server-side, even if validated on frontend
- **No exposed secrets** — never hardcode tokens, keys, passwords, connection strings. Use env vars. Never log secrets, even at debug level
- **Unsafe deserialization** — never deserialize untrusted data without schema validation (Zod, JSON Schema)

## Logic Preservation

The cardinal rule of refactoring and code review: **the observable behavior of the code must not change**.

- **Refactoring ≠ rewriting** — refactoring changes structure (naming, decomposition, patterns) while preserving every input→output mapping. If the user calls a function with the same args and gets a different result, it's not a refactor — it's a rewrite
- **Review suggestions must be behavior-neutral** — when a code reviewer suggests a change, the suggestion must produce identical results for all valid inputs. If a reviewer proposes simplifying an `if/else` chain, the simplified version must handle every branch the same way
- **Don't "fix" intentional behavior** — if code looks wrong but passes tests and handles a known edge case, it's probably intentional. Ask before changing. A workaround with a comment is better than a "clean" version that breaks the edge case
- **Side effects are part of behavior** — logging, metrics, event emission, cache writes are observable. Moving, reordering, or removing them during refactoring changes behavior even if the return value stays the same
- **Verify after refactoring** — after any structural change, the existing tests must still pass without modification. If tests need updating, that's a signal the behavior changed (exception: tests that tested implementation details, not behavior)

## Adaptive Review Depth

Review depth must match **semantic complexity**, not line count. A 1-line change in auth middleware is more critical than 200 lines of i18n translations.

- **Assess before reviewing** — before diving into the diff, determine: what areas are affected (auth, payments, data integrity, UI cosmetics)? What's the blast radius if this code is wrong? The answer sets the depth
- **High-risk signals** (go deep, plan before conclusions):
  - Authentication, authorization, session handling
  - Money, payments, financial calculations
  - Data mutations (INSERT/UPDATE/DELETE), schema changes
  - Cryptography, secrets, tokens
  - Concurrency, shared state, race-prone code
  - Public API contracts (breaking changes)
- **Low-risk signals** (single pass is enough):
  - Translations, copy text, comments
  - CSS/styling, purely visual changes
  - Adding/removing log lines
  - Dependency version bumps (unless major)
  - Test-only changes that don't touch production code
- **When in doubt, go deeper** — a false alarm costs minutes, a missed bug in auth costs days
- **No rigid thresholds** — never use line count, file count, or diff size as the primary factor. They are hints at best. A 3-line regex change can be far more dangerous than a 500-line generated migration

## Testing

- **Testing Pyramid** — many unit tests, fewer integration, minimal e2e
- **AAA Pattern** — Arrange (setup), Act (execute), Assert (verify) in every test
- **Test behavior, not implementation** — test "what it does", not "how it's built". Tests survive refactoring

## Performance

- **Lazy Loading** — load only when needed. Dynamic imports for heavy modules
- **Pagination everywhere** — never return unbounded result sets. Always limit + offset or cursor
- **N+1 Query Prevention** — use joins/includes instead of loops with queries
- **No blocking in async** — never block the event loop with synchronous heavy computation. Use workers, streams, or chunked processing
- **Sequential → parallel** — independent async operations must run concurrently (`Promise.all`), not sequentially (`await` in a loop)
- **Bounded data structures** — arrays, maps, caches, queues must have explicit size limits. Unbounded growth = memory leak in disguise
- **Change-detection guards** — skip no-op updates in loops/handlers. Don't re-render, re-write, or re-send if nothing changed
