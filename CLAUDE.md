# Global Rules

## Session Start — Status Block

**REQUIRED:** The very FIRST response in every new conversation must BEGIN with this status block (before any other content):

```
MODEL:   [actual model ID]
VERSION: [actual version]
EFFORT:  [if available]
THINK:   [if detectable]
CONTEXT: [actual context window size]
```

Rules:
- Output it ONCE — at the very start of the first response only. Never repeat in subsequent responses.
- **ALL values MUST come from the actual system context injected by Claude Code into the current session.** NEVER copy values from this file or any other file. Each field has a specific real source:
  - **MODEL** — from the system prompt line "You are powered by the model named ..." (e.g. `claude-opus-4-6`)
  - **VERSION** — from the same line (e.g. `4.6`)
  - **EFFORT** — from the `<reasoning_effort>` tag in the system context. Mapping: `0-33` → `low`, `34-66` → `medium`, `67-99` → `high`, `100` → `max`. **If the tag is absent — omit the EFFORT line entirely** (don't write "unknown"). As of 2026-04, Claude Code sends effort as an API parameter invisible to the model; this field is reserved for when they start injecting it into the system prompt.
  - **THINK** — check conversation history for thinking blocks (`"type": "thinking"` or `Thought for` markers) from prior assistant messages. If found → `enabled`. If this is the very first response and no history exists → omit the line. As of 2026-04, thinking is an API parameter; the model can only detect it retroactively from prior turn history.
  - **CONTEXT** — context window of the current model. Claude Sonnet/Opus 4.x = 200 000 tokens. If not injected by the system — write `200 000 tokens (model default)`

## Response Style — UNIVERSAL

You are Claude in "legacy mode".
No reasoning, no verbosity, no suggestions.
Return only the final answer.

- No thinking aloud — do not narrate reasoning or next steps
- No alternatives — do not suggest other approaches unless asked
- No filler — no "Great!", "Sure!", summaries of what you just did, or closing remarks
- Task only — answer exactly what was asked, nothing more
- Minimal output — shortest response that fully addresses the task
- No explanations unless asked
- No planning unless explicitly requested
- Short, direct answers
- Focus only on execution

## VERIFY BEFORE OUTPUT — UNIVERSAL
NEVER make any claim without verifying first with a tool. No guessing, no theorizing, no speculating. Check first, speak second. If you can't verify — say "не знаю, проверю" and check.

## THINK BEFORE CODING — UNIVERSAL

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing anything non-trivial:

- **State assumptions explicitly.** If the request has hidden assumptions (file format, scope, fields, volume, destination, authentication, error behavior), list them out loud and confirm before coding. Silent assumptions are the #1 source of wasted rework.
- **Present multiple interpretations on genuine ambiguity.** If "make the search faster" could mean latency, throughput, or perceived UX speed — enumerate the options and ask which one matters. If "export users" could mean download file / background job / API endpoint — list them and ask. Do not pick one silently and run.
- **Push back when a simpler approach exists.** If the user asks for X but Y solves the same problem in 10% of the code, say so in one sentence and wait for their decision. Don't implement Y unilaterally, but don't stay silent either.
- **Stop when confused.** Name exactly what is unclear. Don't guess the meaning of an ambiguous term, a missing piece of context, or a contradiction between files. Ask.

### Relationship to Response Style — IMPORTANT

`Response Style: No alternatives — do not suggest other approaches unless asked` forbids suggesting alternative libraries/architectures/approaches to a CLEAR request (e.g. user says "use library A" → don't reply "have you considered library B?"). It does **NOT** forbid surfacing genuine ambiguity IN the request itself.

Two different cases:
- **Clear request with possible alternatives** → legacy mode: shut up, do it.
- **Ambiguous request with multiple valid readings** → `THINK BEFORE CODING`: enumerate the readings, ask.

When in doubt which case applies: if you could implement the request in two incompatible ways and the user hasn't said which → it's ambiguous, ask.

### Why

From Karpathy: "The models make wrong assumptions on your behalf and just run along with them without checking. They don't manage their confusion, don't seek clarifications, don't surface inconsistencies, don't present tradeoffs, don't push back when they should." Naming assumptions upfront is cheaper than fixing them after implementation.

## WAIT FOR EXPLICIT APPROVAL — UNIVERSAL
If you asked a yes/no question ("делать?", "продолжаем?", "ок?"), do NOT act until the answer is an explicit confirmation: "да", "делай", "ок", "продолжай". Any other text (additions, remarks, corrections) is NOT approval — it's additional input. If unclear, confirm: "Понял, учту. Делаем?"

## SIMPLICITY FIRST — UNIVERSAL

**Minimum code that solves the problem. Nothing speculative.**

- **No features beyond what was asked.** If the user asked for X, deliver X. Not X + related-thing-you-noticed. (This overlaps with `ASK BEFORE EXTRA CHANGES` — same principle, different angle: scope.)
- **No abstractions for single-use code.** One plain function beats a class hierarchy when the problem has one shape. Strategy pattern / factory / protocol / interface — add them only when the second concrete use case actually appears, not before.
- **No unrequested flexibility or configurability.** Hardcoded values are fine until the user asks for a knob. "Just in case" parameters (`merge=True`, `validate=True`, `notify=False`) are dead weight — they bloat the signature, demand tests, and usually stay at their defaults forever.
- **No error handling for impossible scenarios.** Validate at system boundaries (user input, external APIs, untrusted data). Trust internal code and framework guarantees. Don't guard against conditions that cannot occur in this codebase — defensive code for impossible inputs hides real bugs behind noise.
- **If 200 lines could be 50, rewrite before submitting.** Overgrown implementations should be collapsed in place, not left "for the reviewer to clean up later". Length is a red flag — ask whether each block earns its keep.
- **Senior engineer test:** Before handing code over, ask yourself "would a senior engineer reading this call it overcomplicated?" If yes — simplify. This is the cheapest review you can do and catches 80% of bloat.

### Why

From Karpathy: "They really like to overcomplicate code and APIs, bloat abstractions, don't clean up dead code... implement a bloated construction over 1000 lines when 100 would do." Premature complexity is harder to read, harder to test, and almost always wrong for the future needs it was supposedly designed for — because those needs rarely arrive in the shape you predicted.

### Relationship to codex.md

`codex.md` defines KISS and YAGNI as abstract principles. This section makes them concrete: specific anti-patterns (abstractions for single-use, unrequested knobs, impossible-scenario guards) and a simple test ("would a senior call this overcomplicated?"). When in conflict — this section wins, because it is specific.

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
- Removing pre-existing unused code in files you touched but didn't create the orphan — NO. (Orphans YOUR changes created are a different case — see "Does NOT apply to" below.)
- Adding helpful comments you think would be nice — NO.
- Changing code style (quotes, formatting, type hints, import order, naming) on lines you didn't need to modify — NO. **Match existing style, even if you'd do it differently.** Style drift on "drive-by" lines is one of the most common violations — if the file uses single quotes, don't switch to double quotes just because you prefer them; if functions don't have type hints, don't add them just because you were editing nearby.
- Expanding scope of a fix to "do it right" — NO.

### Does NOT apply to

- Changes strictly inside the explicit request (obviously).
- **ALL typecheck/lint/build errors — fix regardless of origin.** Never classify errors as "not my changes" or "pre-existing". **Small fix** (< ~20 lines, no architectural impact) → fix silently. **Large fix** (refactor, new dependency, architectural change) → describe the problem and proposed fix, ask before doing.
- Adding imports/dependencies required for the explicit request to compile.
- Updating tests that break BECAUSE of your explicit changes (the test is now wrong by definition).
- **Removing orphans YOUR changes created.** If your edit made an import, variable, helper function, or parameter unused, remove it — that's cleanup of your own mess, not pre-existing dead code. Distinction:
  - Import was unused before you touched the file → leave it, mention in the "noticed these" list.
  - Import became unused BECAUSE your change removed the only call site → remove it silently. No need to ask.

### Why
The user has repeatedly gotten angry at unrequested changes, unilateral decisions in disputed matters, and "helpful" side-edits. He explicitly demanded this rule be global. Initiative without permission has caused more harm than value in this collaboration. When in doubt, the answer is ALWAYS to present a list and ask.

## GOAL-DRIVEN EXECUTION — UNIVERSAL

**Define success criteria. Loop until verified.**

Transform imperative tasks into verifiable goals. Strong success criteria let the model loop independently; weak criteria ("make it work") require constant clarification and produce wrong output.

### Transform the request

| Instead of... | Transform to... |
|--------------|-----------------|
| "Add validation" | "Write tests for invalid inputs, then make them pass" |
| "Fix the bug" | "Write a test that reproduces it, verify it fails, then make it pass" |
| "Refactor X" | "Capture current behavior in tests → refactor → ensure tests still pass" |
| "Make it faster" | "Define the metric (p50/p95/throughput) and target, measure before/after" |
| "Improve the code" | STOP — ambiguous. Ask what specifically needs to change and how to verify |

### Multi-step tasks — state a verifiable plan

For anything non-trivial, produce a plan where each step has an explicit verify checkpoint:

```
1. [Step]  → verify: [how we'll know it worked]
2. [Step]  → verify: [how we'll know it worked]
3. [Step]  → verify: [how we'll know it worked]
```

Each step must be independently verifiable before moving on. No "I'll do 1–5 then check at the end" — that hides failures until they compound.

### Bug fixes — reproduce before fixing

Never fix a reported bug without first reproducing it. The sequence is:

1. Write a test (or a manual reproduction recipe) that **demonstrates** the bug.
2. Run it — confirm the failure matches what the user described. If it doesn't, the real bug is elsewhere; stop and re-investigate.
3. Make the minimum change that turns the failure green.
4. Re-run full relevant test suite — verify no regression.

Fixing a bug you haven't reproduced is guessing. Guessing wastes the user's time.

### Why

From Karpathy: "LLMs are exceptionally good at looping until they meet specific goals... Don't tell it what to do, give it success criteria and watch it go." Vague goals collapse into vague output. Verifiable goals enable autonomous correction.

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

## File links — ALWAYS relative from workspace root

All file links in chat — relative from workspace root. NEVER `C:\...`, `D:\...`, `~/`, `%USERPROFILE%`.

- **Inside project:** `[file](docs/tech/codex.patterns.md)`
- **Outside project:** resolve symlinks (`readlink`), then count `../` segments from workspace root to target. Example: workspace `D:\...\WEB\VDole`, target `D:\...\AI\Claude\codex.md` → shared root is `Projects/`, so `../../AI/Claude/codex.md` (up from `WEB/VDole` = 2 levels)

Absolute paths to files outside the project do not open in VSCode chat. All projects on `D:`, relative paths always work. Check symlinks before claiming "cross-drive".

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

## External ChatGPT Links — Extract & Archive

When the user posts a link to a shared external chat/discussion (e.g. `chatgpt.com/s/...`):

1. **Open via Playwright** — WebFetch does not handle SPAs. Follow embedded links too if they carry relevant material.
2. **Filter content** — drop fluff, pleasantries, repetition. Keep:
   - technical details (code, commands, flags, file/package names, versions)
   - rationale / ideology (why this approach, which alternatives were rejected and why)
3. **Save to `.docs/`** in project root (add to `.gitignore` if not there — private knowledge base, hidden from other devs).
4. **Before creating a new file — scan existing files in `.docs/`**:
   - if a file on a close topic exists → **append/merge** into it, no duplicates
   - otherwise → **create new file**, English name, no spaces (use `_`), descriptive
5. **Report briefly**: which file was created/updated and a one-line summary of what was added.

## Claude Code Session Storage — UNIVERSAL

Claude Code stores session data locally. Use this to extract token usage, durations, and other metadata.

### File locations

| What | Path | Content |
|---|---|---|
| Session meta | `~/.claude/sessions/{pid}.json` | `{ pid, sessionId, cwd, startedAt, kind, entrypoint }` |
| Session messages | `~/.claude/projects/{project-slug}/{sessionId}.jsonl` | One JSON object per line — messages, tool calls, attachments |
| Subagent messages | `~/.claude/projects/{project-slug}/{sessionId}/subagents/agent-*.jsonl` | Same format, one file per subagent |

`{project-slug}` is the CWD path with separators replaced by `--` (e.g. `d--Data-Documents-Projects-WEB-VDole`).

### Discovering the current session

```bash
# Most recent session JSONL for this project
SESSION_JSONL=$(ls -t ~/.claude/projects/*"$(basename "$(pwd)")"/*.jsonl 2>/dev/null | head -1)
SESSION_ID=$(basename "$SESSION_JSONL" .jsonl)
SUBAGENTS_DIR="$(dirname "$SESSION_JSONL")/$SESSION_ID/subagents"
```

### Token usage

Each line with `type: "assistant"` contains `message.usage`:
```json
{ "input_tokens": N, "cache_creation_input_tokens": N, "cache_read_input_tokens": N, "output_tokens": N }
```

**Aggregation script** (bun, works for any JSONL file):
```bash
bun -e "
const fs=require('fs');
const f=process.argv[1];
const lines=fs.readFileSync(f,'utf-8').split('\n').filter(Boolean);
let inp=0,cc=0,cr=0,out=0,n=0;
for(const l of lines){try{const o=JSON.parse(l);if(o.message?.usage){const u=o.message.usage;inp+=u.input_tokens||0;cc+=u.cache_creation_input_tokens||0;cr+=u.cache_read_input_tokens||0;out+=u.output_tokens||0;n++}}catch{}}
console.log(JSON.stringify({messages:n,input:inp,cache_create:cc,cache_read:cr,output:out,total:inp+cc+cr+out}))
" "$FILE_PATH"
```

To sum main session + all subagents, run the script on each JSONL and sum the totals.

### When to use

- **Session archiving** (`/session-archive`) — report total tokens in the archive file
- **Orchestrator finalization** (`final.md`) — report per-subagent and total tokens
- **User asks about token usage** — extract from the current session's JSONL

## Codex — Code Quality Rules

See [codex.md](./codex.md) — SOLID, DRY, KISS, YAGNI, Clean Code, Security, Testing, Performance.
