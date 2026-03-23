---
name: pre-deploy-autotests
description: Run ALL autotests (unit, integration, e2e). Reads project-specific steps from ./tests/skills/pre-deploy-autotests.md
disable-model-invocation: false
allowed-tools: AskUserQuestion,Bash(bun *),Bash(bunx *),Bash(powershell.exe *),Bash("$LOCALAPPDATA/Programs/Cursor/*"),Read,mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot
model: sonnet
---

# Pre-Deploy Autotests — Universal Runner

Run project-specific test suites with standardized progress output, pre-flight checks, and error handling.

<!-- Project-specific configuration: ./tests/skills/pre-deploy-autotests.md
     This is a global skill — the actual steps, commands, pre-flight checks,
     and paths are defined per-project in the local file above.
     See existing projects for format examples. -->

## Execution

### Step 1: Read local prompt

Read `./tests/skills/pre-deploy-autotests.md` from the project root.

- **If file exists** — parse all sections: `## Pre-flight`, `## Steps`, `## On success`, `## On failure`.
  Then go to Step 2.

- **If file NOT found** — print:

```
⚠️ Файл ./tests/skills/pre-deploy-autotests.md не найден.

Создайте файл с описанием тестов для этого проекта:

## Pre-flight
- MCP Playwright: `mcp__playwright__browser_navigate` with url `about:blank`
- Dev server: http://localhost:3000/api/health

## Steps
1. Unit tests: `bun test tests/unit/`
2. Integration tests: `bun test tests/integration/`
3. E2E tests: `bunx playwright test`

## On success
All tests green

## On failure
Tests failed — fix before deploy
```

Then STOP. Do not run anything.

### Step 2: Pre-flight checks

Execute each check from `## Pre-flight` section. The local file defines what to check and how.

Common patterns the local file may specify:
- **MCP check** — try calling an MCP tool. If fails → report and stop.
- **Dev server check** — hit a URL. If fails → ask user via AskUserQuestion whether to continue without E2E or stop entirely.

Follow the local file's instructions for pre-flight behavior exactly.

### Step 3: Run steps with progress

For N total steps, print:

```
**Autotests** [0/N]
```

For each step:

1. Print BEFORE running:
   ```
   [i/N] Step Name -- running...
   ```

2. Run the command.

3. Print IMMEDIATELY after:
   ```
   [i/N] Step Name -- PASS (N tests)
   ```
   or:
   ```
   [i/N] Step Name -- FAIL (N passed, M failed)
   ```

**IMPORTANT:** Run ALL steps even if earlier ones fail (unless pre-flight explicitly skipped a step).

### Step 4: Summary table

After all steps, show:

| Suite | Result |
|-------|--------|
| Step Name | PASS/FAIL/SKIP (details) |

### Step 5: Verdict

- Use text from `## On success` if all passed (default: "All tests green")
- Use text from `## On failure` if any failed (default: "Tests failed — fix before deploy")
- If steps were skipped — note it separately

## Rules

- Do NOT fix any errors — only report them
- Run ALL steps regardless of failures (except explicitly skipped by pre-flight)
- Communicate in Russian
