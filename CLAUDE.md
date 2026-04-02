# Global Rules

## VERIFY BEFORE OUTPUT — UNIVERSAL
NEVER make any claim without verifying first with a tool. No guessing, no theorizing, no speculating. Check first, speak second. If you can't verify — say "не знаю, проверю" and check.

## File naming — no spaces
NEVER use spaces in file or directory names when creating new files. Use underscores `_` instead. This applies to all paths and filenames without exception. If you encounter an existing file with spaces in its name, notify the user via AskUserQuestion before proceeding: "Файл содержит пробелы в имени: `<path>`. Переименовать?"

## No duplication of rules
NEVER duplicate rules across CLAUDE.md, CLAUDE.local.md, and memory files. Each rule lives in exactly ONE place. Memory is only for things NOT already in CLAUDE.md files.

## Data access — use dedicated modules
NEVER write inline `db.select/insert/update` in routes, middleware, or handlers. Each DB table MUST have a dedicated data access module with ALL read and write functions. Routes call the module, not the ORM directly. Before adding a new query — check if the module already has a suitable function.
```
// BAD:  in route
const user = await db.select().from(users).where(eq(users.userId, id))
await db.update(users).set({ lang }).where(eq(users.userId, id))

// GOOD: in route
const user = await usersDb.findById(id)
await usersDb.updateLang(id, lang)
```

## .mcp.json — disabled servers are intentional
User moves MCP servers to `mcpServers-off` to save tokens. This is normal practice. NEVER flag this in code reviews or mention as a concern.

## Codex — Code Quality Rules

See [codex.md](./codex.md) — SOLID, DRY, KISS, YAGNI, Clean Code, Security, Testing, Performance.
