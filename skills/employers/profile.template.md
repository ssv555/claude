# Project profile — `<PROJECT_NAME>`

> Per-project profile for the global `emp-NN-*` skills. Lives at `<project>/.claude/skills/employers/profile.md` (preferred) or `<project>/.docs/employers/profile.md` (legacy back-compat). Required reading for every employee role at the start of its run.

## 1. Identity

- **Project name:** `<PROJECT_NAME>`
- **One-line pitch:** <what the product is, in plain language>
- **Started:** YYYY-MM-DD
- **Public-facing tech mention bans (frontend only):** <list techs that exist in the project but should NEVER appear in user-facing UI/landing/About pages — leave empty if none>

## 2. Domain & terminology

> Canonical role names that BA and reviewer enforce. Do NOT use synonyms.

| Term | Role / meaning |
|---|---|
| `<RoleA>` | <description> |
| `<RoleB>` | <description> |
| `<Platform>` | <how the platform itself acts> |

Two (or more) user-facing apps:
- **`<App1>`** — <which role it serves, key features>
- **`<App2>`** — <which role it serves, key features>

## 3. Stack

### Frontend

<list libs and tools, e.g. bun, vite, TypeScript, React, ChosenUILib, Tailwind, ChosenORM, ChosenServerFw, i18n lib (langs), state management, etc.>

### Backend / static server

<list libs and tools>

### Database

<DB engine, special certifications/compliance, ORM, schema doc path>

### Bots / integrations (optional)

<list>

### Other services (optional)

<list>

## 4. Stack rules (THIS IS THE CHEAT-SHEET ROLES READ)

> Every employee role keeps these rules in head while working. Architect's §9 / §10 / Reviewer's Pass-1.4 / Developer's self-check all reference this list.

### 4.1 Runtime / package manager

- Runtime: `<bun | node | deno | python>` only. Never `<list forbidden>`.
- Dev server: <"HMR running, NEVER restart" | "ok to restart">

### 4.2 Database conventions

- Naming: <snake_case tables / camelCase ORM fields / etc.>
- Primary keys: <`uuid` defaultRandom | `serial` for lookups | etc.>
- Money type: <`numeric(14,2)` | etc.> — **NEVER** float
- Foreign keys: <forbidden / required / case-by-case>
- Timestamps: <`timestamp with timezone` + `defaultNow()` | etc.>
- Migrations: <"only via seed.ts + db:push" | "Drizzle Kit" | etc.>
- DDL exceptions: <e.g. lookup tables use serial PK>

### 4.3 Layering rules

- All DB access in routes/middleware MUST go through `<dedicated data access modules>` — NO inline `db.select/insert/update`.
- Each table has a dedicated module: <e.g. `back/src/db/{table}.ts`>.
- Routes do business logic; they call data access modules, never the ORM directly.
- Auth: `<auth middleware name>` on protected routes; `<admin middleware name>` on admin-only.
- Rate limiting: `<rate limiter location>` on all mutations.

### 4.4 Frontend rules

- Internal navigation: `<Link to="...">` (or framework equivalent), NEVER `<a href>` — full-page reload destroys state.
- Toast notifications: `<library>` (e.g. sonner) — `toast.error/success` for user-facing messages.
- API client: `<library>` (e.g. Eden Treaty / tRPC / openapi-fetch).
- State: `<library>` (e.g. TanStack Query) — query keys in dedicated file (path).
- localStorage vs DB: UI preferences (theme, view mode, sidebar, table filters/sort, page size) → localStorage. DB only for account-bound, money, legal, cross-device data.
- Validation: `<library>` (e.g. zod) on ALL API inputs.

### 4.5 Error logging

- In `catch` blocks: `<ConsoleErrLog() | structured logger>`, NEVER raw `console.error`.
- Silent catches: must have `// silent: <reason>` comment.
- Exceptions: <list scripts/modules where raw console.error is allowed, e.g. CLI scripts, logger internals>.

### 4.6 i18n

- Languages: <e.g. ru, en>. Locale files: <path>.
- Both/all locales MUST stay synchronized — orphan keys forbidden, missing keys CRIT.
- After editing locale files: <e.g. run `/version-up` so cache busts via `?v=APP_VERSION`>.
- Number/date/currency formatting: through i18n formatter, not hardcoded.

### 4.7 Other

- Email subjects (if applicable): `<format>` (e.g. "<PROJECT_NAME> — ...")
- Fonts: self-hosted, must include all locale glyphs (e.g. Cyrillic).
- Container padding: <e.g. `p-4` on PopoverContent / Card / Dialog>.
- Buttons: <e.g. always visible border>.
- Route headers: <e.g. breadcrumbs, not plain text>.

## 5. Code paths (file structure)

> Architect uses these for Glob; developer uses for layer order; reviewer uses for scope.

### Backend
- App entry: `<path>` (e.g. `back/src/app.ts`)
- Constants: `<path>`
- Version file: `<path>`
- Schema (DDL): `<path>`
- Data access: `<path>`
- Routes: `<path>`
- Middleware: `<path>`
- Lib (utilities): `<path>`
- Shared types: `<path>`
- Bots (if any): `<paths>`

### Frontend
- Routes: `<path>` (e.g. `front/src/routes/`)
- Components: `<path>`
- Lib (api, query keys): `<paths>`
- Locales: `<path>` (e.g. `front/public/locales/{ru,en}/`)
- Static styles / tokens: `<path>` (if applicable)

### Tests
- Server unit: `<path>`
- Server integration: `<path>`
- Frontend: `<path>`
- E2E: `<path>`

### Docs
- DB schema doc: `<path>` (REQUIRED — Architect reads this)
- Code patterns doc: `<path>` (e.g. `docs/tech/codex.patterns.md` — Reviewer reads this if exists)
- Business docs: `<path>` (e.g. `docs/business/*` — BA reads this)
- Tech docs: `<paths>`

### Aliases (if applicable)

- `@/` → `<path>`
- `@server/` → `<path>`

## 6. Layer order for developer

When implementing per architect's §4, follow this order (types ready before consumers):

1. DB schema (`<schema path>`) — DDL changes
2. Data access (`<data access path>`) — new/changed functions
3. Routes (`<routes path>`) — endpoints
4. Middleware (`<middleware path>`) — if touched
5. Frontend types/api (`<lib path>`) — types, API client, query keys
6. Frontend components/pages (`<paths>`) — UI
7. i18n (`<locales path>`) — all languages synchronously

## 7. Self-gate commands (developer runs all before sdача)

```bash
<typecheck command>
<lint command>
<build command>
<server unit tests command>
<server integration tests command>
<other project-specific gate commands>
```

## 8. Code-quality command set (reviewer runs in Pass 1 if file `<project>/tests/skills/emp-04-reviewer.md` exists)

> Reviewer-specific commands that check content/consistency between code and static assets. NOT typecheck/lint/build (those belong to `pre-deploy-check-build`). Examples: i18n key↔code sync, hardcoded UI strings, dead translation cleanup.

```bash
<command 1>
<command 2>
```

## 9. Sealed registry

- **Path:** `<absolute path to registry, e.g. ~/.claude/sealed/sealed-<project>.json>`
- **Format:** JSON with groups; group has `sealed: true|false` and `files: [...paths]`. Architect collects all `files` from groups with `sealed: true` and compares against the plan.
- **Marker fallback:** any file with `// @sealed` in the first line is also sealed.
- **Heuristics if registry missing:** look for `<typical sealed paths in this project: auth, crypto, payment, etc.>`.

## 10. Compliance / regulatory context

> BA includes this in every report's §6.5; Reviewer audits PII/audit/sec accordingly.

- **Personal data (PII):** <yes/no, categories, jurisdiction>
- **Financial operations:** <yes/no, AML/KYC, audit trail requirements>
- **User consents:** <required types>
- **Data retention:** <storage/deletion, right-to-be-forgotten obligations>
- **Public commitments:** <ToS, privacy policy, public offer>

## 11. Markdown link conventions

- **Pipeline-folder reports** (`00_task.md` … `final.md`): paths relative to the md file. Pipeline folder is at `<pipeline_root>/<slug>/` — depth from project root: `<N>` levels (so `<N>×../` to reach project root from a pipeline-folder md).
- **Project files in reports:** `[<filename>](<../>×N/<rel-path-from-project-root>)`
- **Sibling pipeline files:** `[01_ba.md](./01_ba.md)`
- **Chat with user (NOT in reports):** paths from project root (`[file.ts:42](src/file.ts#L42)`).

For VDole-style `pipeline_root: .docs/employers/pipeline` → 4 levels of `../`. For `pipeline_root: .claude/skills/employers/pipeline` → 5 levels.

## 12. Environment / dev URLs (optional, but useful)

- Production: `<URL>`
- Dev / staging: `<URLs>`
- Local ports: <list>

## 13. Anything else specific to this project

<free-form section for project-specific quirks not captured above — anything employee roles need to know but doesn't fit the schema above>
