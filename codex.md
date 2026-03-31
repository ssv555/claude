# Codex — Code Quality Rules

- SOLID (S, O, L, I, D)
- DRY after 3 occurrences
- Composition > inheritance (max depth 2)
- Separation: DB in services, validation in schemas, routing in routes, UI in components
- KISS, YAGNI, Boy Scout, Least Surprise
- Function ~30 lines, component ~150 lines, route file ~300 lines
- Max nesting 3 — early return
- Naming: var = "what", func = "what does", bool = `is/has/can/should`
- Command-Query Separation
- Law of Demeter — no `a.b.c.d`
- No magic numbers — constants
- `const` > `let`, immutability, pure functions, side effects at edges
- async/await, Promise.all

## Errors

- Every `catch` → `console.error('action', { context })`. Silent only with `// silent: <reason>`
- Structured logging objects, not strings
- Dev: fail fast. Prod: graceful + server logs

## Security

- OWASP Top 10
- Validate inputs server-side, sanitize output
- Rate limiting on mutations/auth/AI
- No `dangerouslySetInnerHTML`, no `eval`
- `timingSafeEqual` for secrets
- Cookies: HttpOnly, SameSite, Secure, expiration

## Testing

- Pyramid: unit > integration > e2e
- AAA pattern
- Test behavior, not implementation

## Performance

- Dynamic imports for heavy stuff
- Pagination everywhere
- N+1: joins, not loops
- `useMemo`/`useCallback` only when measured

## UI

- Semantic HTML + keyboard accessible
- Messages → toast
- `p-4` on popover/card/dialog
