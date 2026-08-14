---
name: pre-deploy-check-build
description: Run all error checks (typecheck, lint, build) before deploy. Reads project-specific steps from ./tests/skills/pre-deploy-check.md
disable-model-invocation: false
allowed-tools: Bash(bun *),Bash(npm *),Bash(npx *),Bash(bash *),Bash(node *),Read
model: sonnet
---

# Pre-Deploy Check — Universal Runner

Run project-specific quality checks with progress output and error handling.

<!-- Project-specific configuration: ./tests/skills/pre-deploy-check.md
     This is a global skill — the actual steps, commands, and paths
     are defined per-project in the local file above.
     See existing projects for format examples. -->

## Execution

### Step 1: Read local prompt

Read `./tests/skills/pre-deploy-check.md` from the project root.

- **If file exists** — parse `## Steps` section. Each step is a line: `N. Name: \`command\``
  Also read any `## Pre-flight`, `## On success`, `## On failure` sections if present.
  Then go to Step 2.

- **If file NOT found** — print:

```
⚠️ Файл ./tests/skills/pre-deploy-check.md не найден.

Создайте файл с описанием шагов для этого проекта:

## Steps
1. TypeScript: `bun run typecheck`
2. ESLint: `bun run lint`
3. Build: `bun run build`

## On success
Ready for deploy

## On failure
Fix errors before deploy
```

Then STOP. Do not run anything.

### Step 2: Pre-flight (optional)

If `## Pre-flight` section exists in the local file — execute those checks first.
If any pre-flight check fails, report it and STOP.

### Step 3: Run steps with progress

For N total steps, print:

```
**Pre-deploy Check** [0/N]
```

For each step:

1. Print BEFORE running:
   ```
   [i/N] Step Name -- checking...
   ```

2. Run the command.

3. Print IMMEDIATELY after:
   ```
   [i/N] Step Name -- PASS
   ```
   or:
   ```
   [i/N] Step Name -- FAIL (error details)
   ```

**IMPORTANT:** Run ALL steps even if earlier ones fail. Never stop on first error.

### Step 4: Summary table

After all steps, show:

| Check | Result |
|-------|--------|
| Step Name | PASS/FAIL (details) |

### Step 5: Verdict

- Use text from `## On success` if all passed (default: "Ready for deploy")
- Use text from `## On failure` if any failed (default: "Fix errors before deploy")

## Rules

- Do NOT fix any errors — only report them
- Run ALL steps regardless of failures
- Communicate in Russian
