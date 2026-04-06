---
name: code-reviewer
description: "Code review of changed files against Codex rules (SOLID, DRY, Security, Performance, Correctness). Use when the user wants a code review, quality check, or asks to review changes."
disable-model-invocation: false
allowed-tools: Bash(git *), Bash(bun test *), Bash(powershell *), Read, Grep, Glob, Edit, Write
model: opus
effort: max
---

# Code Reviewer (ultrathink)

<!-- AskUserQuestion does NOT work in subagents/hooks/background agents.
     This skill uses ~/.claude/scripts/dialog.ps1 for interactive prompts instead.
     See dialog.ps1 header for details. -->

Review changed code against **Codex** (`~/.claude/codex.md`) — the single source of engineering rules.

## Scope

Only review changes introduced in the diff. Do NOT flag pre-existing issues.

## Step 1: Get the diff

```bash
git diff HEAD
```

If no unstaged changes, try staged:

```bash
git diff --cached
```

If neither has changes, diff last commit:

```bash
git diff HEAD~1..HEAD
```

If the user provides specific commits or a range — use that instead.

## Step 2: Read changed files

Read the full files (not just diff hunks) to understand surrounding context.

## Step 3: Read Codex

Read `~/.claude/codex.md` to load the current rule set. Apply every rule from the list to the diff.

## Step 4: Assess complexity

Before analyzing, evaluate semantic risk of the changes:
- **What areas are affected?** Auth, payments, data mutations, crypto, concurrency, public API → go deep, think through edge cases
- **What's the blast radius?** Translations, styling, logs, test-only → single pass is enough
- **Never judge by line count** — 1 line in auth > 200 lines of i18n

Adapt your analysis depth accordingly. When in doubt, go deeper.

## Step 5: Analyze

Review the diff against ALL codex rules. Classify each finding:

| Level | Meaning | Action |
|-------|---------|--------|
| P0 | Critical — security vulnerability, data loss, crash | Must fix |
| P1 | Major — bug, performance regression, broken feature | Must fix |
| P2 | Minor — code smell, clarity, inconsistency | Nice to fix |
| P3 | Suggestion — optional improvement | Optional |

### Review dimensions (mapped to codex):

- **Correctness** — edge cases, off-by-one, type coercions, control flow
- **Security** — OWASP, input validation, exposed secrets, unsafe deserialization
- **Performance** — N+1, blocking async, unbounded structures, missing parallelization
- **Data integrity** — race conditions, transactions, TOCTOU, partial failure
- **Architecture** — SOLID, DRY, separation of concerns, decomposition limits
- **Code hygiene** — redundant state, stringly-typed, leaky abstractions, comments
- **Clean code** — naming, guard clauses, CQS, Law of Demeter, magic values

## Step 6: Output review

If no issues found:

```
Замечаний нет
```

Then STOP. Skip steps 7–8.

If issues found, output in Russian:

```
## Code Review

**Вердикт**: [APPROVE | NEEDS FIX | DISCUSS]

### Находки

| P | Проблема | Файл:строка |
|---|----------|-------------|
| P0 | Описание | file:line |

### Детали

#### [P0] Заголовок
**Файл:** `path/to/file.ext:line`

Описание проблемы и почему это важно.

**Исправление:**
\`\`\`
code suggestion
\`\`\`
```

**Rules:**
- `APPROVE` — no P0/P1 findings → skip steps 7–8
- `NEEDS FIX` — has P0 or P1 → continue to step 7
- `DISCUSS` — ambiguous → continue to step 7
- P0/P1 — always include detailed write-up + suggested fix
- P2/P3 — table entry only, detail section only if code suggestion helps
- Keep it concise — no praise, no filler

## Step 7: Confirm edits

If verdict is `NEEDS FIX` or `DISCUSS`, ask via dialog:

```bash
powershell -nop -f ~/.claude/scripts/dialog.ps1 -Mode custom -Title "Code Review" -Agent "Code Reviewer" -Message "Найдены P0/P1 замечания. Применить исправления?" -Options "fix:Применить исправления,skip:Пропустить"
```

- Result `fix` → apply all P0/P1 fixes using Edit tool. Follow Logic Preservation rule — fix only the flagged issue, do not change surrounding code. After applying, continue to step 8.
- Result `skip` → STOP.

## Step 8: Test decision

After edits were applied, assess whether tests are needed:

- **Tests needed if:** logic changed, new branches added, error handling modified, API contracts affected
- **Tests NOT needed if:** only naming/formatting/comments changed, only imports reordered, only constants moved

If tests are needed, ask via dialog:

```bash
powershell -nop -f ~/.claude/scripts/dialog.ps1 -Mode custom -Title "Tests" -Agent "Code Reviewer" -Message "Правки затронули логику. Запустить тесты?" -Options "run:Запустить тесты,skip:Пропустить"
```

- Result `run` → run `bun test` (or project-specific test command from `package.json`). Report results.
- Result `skip` → STOP.

If tests are NOT needed — STOP silently, do not ask.
