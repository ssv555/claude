# Global Rules

## VERIFY BEFORE OUTPUT — UNIVERSAL
NEVER make any claim without verifying first with a tool. No guessing, no theorizing, no speculating. Check first, speak second. If you can't verify — say "не знаю, проверю" and check.

## WAIT FOR EXPLICIT APPROVAL — UNIVERSAL
If you asked a yes/no question ("делать?", "продолжаем?", "ок?"), do NOT act until the answer is an explicit confirmation: "да", "делай", "ок", "продолжай". Any other text (additions, remarks, corrections) is NOT approval — it's additional input. If unclear, confirm: "Понял, учту. Делаем?"

## ASK BEFORE EXTRA CHANGES — UNIVERSAL

**Do ONLY what the user explicitly asked. Nothing more.**

If while working on a task you notice other things that "should" be changed — bugs, inconsistencies, security concerns, missing tests, code quality issues, obvious improvements, related fixes, additional translations, cleanup, refactors — **do NOT touch them**. Collect them into a list and show that list to the user BEFORE touching any file outside the direct scope of the request.

### The rule

1. **Default is NO action.** Claude has no standing authorization to make any edit the user did not explicitly request.
2. **Collect, don't fix.** When you notice something out of scope, add it to a mental/written list. Do NOT start editing.
3. **Present as a numbered list.** Format:
   > Пока работал, заметил эти вещи, которые ты не просил — хочешь ли что-то из этого сделать?
   > 1. <item 1 — what it is, where, why it matters>
   > 2. <item 2 ...>
   > 3. ...
4. **Wait for explicit approval.** User must say which items to do (by number, by name, or "все"/"ничего"). Silence or ambiguity = NO.
5. **Single targeted fixes only.** If the user says "fix #2", do only #2, not #2 + related cleanup.

### Applies to

- "While I'm here I'll also fix X" — NO.
- "This naming is inconsistent, I'll rename it" — NO.
- "Obvious typo in an unrelated file" — NO.
- "Missing test coverage here, I'll add it" — NO.
- "Better UX would be to also show Y" — NO.
- "This function is ugly, quick refactor" — NO.
- Removing unused code that you touched but didn't break — NO.
- Adding helpful comments you think would be nice — NO.
- Expanding scope of a fix to "do it right" — NO.

### Does NOT apply to

- Changes strictly inside the explicit request (obviously).
- **ALL typecheck/lint/build errors — fix regardless of origin.** Never classify errors as "not my changes" or "pre-existing". **Small fix** (< ~20 lines, no architectural impact) → fix silently. **Large fix** (refactor, new dependency, architectural change) → describe the problem and proposed fix, ask before doing.
- Adding imports/dependencies required for the explicit request to compile.
- Updating tests that break BECAUSE of your explicit changes (the test is now wrong by definition).

### Why
The user has repeatedly gotten angry at unrequested changes, unilateral decisions in disputed matters, and "helpful" side-edits. He explicitly demanded this rule be global. Initiative without permission has caused more harm than value in this collaboration. When in doubt, the answer is ALWAYS to present a list and ask.

## File naming — no spaces
NEVER use spaces in file or directory names when creating new files. Use underscores `_` instead. This applies to all paths and filenames without exception. If you encounter an existing file with spaces in its name, notify the user via AskUserQuestion before proceeding: "Файл содержит пробелы в имени: `<path>`. Переименовать?"

## Windows batch files MUST have CRLF line endings — UNIVERSAL

After editing or writing any `.cmd` / `.bat` file on Windows, ALWAYS verify and restore CRLF line endings (`\r\n`). The `Edit` and `Write` tools save files with LF-only line endings, which silently corrupts batch files — CMD eats the first 1–2 characters of each line and produces bizarre errors like `'tlocal' is not recognized`, `'cp' is not recognized`, `'et' is not recognized` (from `setlocal`, `chcp`, `set`). The file LOOKS fine in a text editor but is broken at runtime.

**Applies to**: `.cmd`, `.bat`, any Windows-only script file. PowerShell (`.ps1`) tolerates LF, so it's not affected, but when in doubt — use CRLF on Windows.

**How to apply after every edit**:

```bash
cd "<project>" && unix2dos <file>.cmd
```

Or if `unix2dos` isn't installed:

```bash
powershell -nop -c "$p='<file>.cmd'; $c=[IO.File]::ReadAllText($p); $c=$c -replace \"`r`n\",\"`n\" -replace \"`n\",\"`r`n\"; [IO.File]::WriteAllText($p,$c)"
```

Verify after with `od -c <file>.cmd | head -3` — first line must end with `\r \n`, not just `\n`.

**Why**: I edited `VDole/run_all_update.cmd` with Edit tool, the file ended up LF-only, CMD parsed it as garbage and ate the first chars of every command — entire script broken, user ran it and got a wall of `'X' is not recognized` errors. Completely wasted run.

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

## RETRIES FOR EXTERNAL INTEGRATIONS — UNIVERSAL

**Any call that leaves the local machine MUST have retry logic with visible error output. By default, not on request.**

This is a universal programming rule, not a project convention. Transient failures (DPI resets, flaky mirrors, brief ISP blips, rate-limit bursts, 502/503 spikes) are the normal state of the internet — treating them as fatal is broken code. Writing external integrations without retries is "через жопу" and will be rejected.

### Applies to

- **Scripts** (bash/cmd/powershell/ps1): `git pull/push/fetch/clone`, `bun/npm/pnpm/yarn install/update/upgrade/add`, `curl`, `wget`, `apt`, `brew`, `pip`, deploy commands hitting remote hosts, `ssh` / `scp` / `rsync` to remote hosts.
- **Application code**: any `fetch` / `axios` / HTTP client call, third-party API calls (OAuth providers, payment gateways, SMS/email gateways, maps, captcha, AI providers, webhooks), remote DB connections on non-local hosts, S3 / object storage, queue publish/consume.

### Does NOT apply to

- Purely local operations: `typecheck`, `lint`, local unit tests, local file I/O, local DB on the same host, local builds. Retrying a local failure hides bugs — fix the root cause instead.

### Requirements

1. **Default params**: 3 attempts total, short backoff (start ~2s, exponential for backend code).
2. **Visible errors on every failed attempt** — not just the last one. The user/operator must see WHAT went wrong on attempt 1 before attempt 2 runs. Silent `[retrying...]` with no error body is unacceptable.
3. **One shared helper** — factor `run_with_retry` / `retryFetch` / `withRetry` once and reuse it. Don't inline the loop per call site.
4. **Log the attempt number** on each retry (`[attempt 2/3 failed — error below:]`) so transient failures are observable in logs.
5. **Retry only on retryable errors** in backend code: network errors, 5xx, 429, timeouts. NOT on 4xx client errors (400/401/403/404) — those won't fix themselves. In scripts, retry on any non-zero exit (can't distinguish cheaply).
6. **Don't retry non-idempotent writes** without an idempotency key (payment charges, "create order" POSTs). If unsure, ask.

### Why

User explicitly flagged this after I wrote `run_all_update.cmd` for VDole without retries and it failed on a GitHub DPI reset. His words: "Я думал, у тебя мозгов хватит самому так сделать. Вообще-то, правильно, так делают, когда внешние интеграции идут." And then again when the retry logic I added didn't show errors on intermediate attempts: "с выводом ошибок". This is baseline craftsmanship for anyone writing code that touches the network — skipping it is a quality defect, not an optimization.

### Not in conflict with ASK BEFORE EXTRA CHANGES

Retries on external integrations are part of correctly implementing the request, not a side-quest. When the task is "write a script that calls X over the network", retries are implicit in "correctly". No need to ask first.

## File links — resolve symlinks, use relative paths

When referencing files outside the current project, ALWAYS:
1. Check if the path is a symlink (`readlink` / `ls -la`)
2. Resolve to the real path
3. Build a relative path from the project root to the real target

`~/.claude` → `D:\Data\Documents\Programming\Projects\AI\Claude\`. All projects are on D:, relative paths work. Never claim "cross-drive, impossible" without checking symlinks first.

## AskUserQuestion — not available in subagents/hooks

`AskUserQuestion` works ONLY in the main session. Subagents (Agent tool), background agents, and hook-triggered agents CANNOT use it — it is blocked at system level.

**Replacement:** `~/.claude/scripts/dialog.ps1` — PowerShell GUI dialog that works from any context. When writing or editing a skill that may run outside main session, use `dialog.ps1` instead of `AskUserQuestion`. Add `Bash(powershell *)` to `allowed-tools`.

## Git — UNIVERSAL

- **NEVER run `git commit` or `git push`**. User executes manually. Claude outputs the command in chat only.
- All other git commands (`status`, `diff`, `log`, `pull`, etc.) — through Claude Code Bash tool only, never external terminals. Ensures PreToolUse hooks fire correctly.

### Command format for user

```
cd /d <project_path> && git add -A && git commit -m "msg" && git pull --rebase && git push
```

- `cd /d <path>` — Windows CMD syntax
- `git add -A` — all files
- `git pull --rebase` before push — multiple devs on same branch
- Full Windows paths, never `~/` or Unix

## Codex — Code Quality Rules

See [codex.md](./codex.md) — SOLID, DRY, KISS, YAGNI, Clean Code, Security, Testing, Performance.
