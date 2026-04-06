---
name: git-push-all
description: "Scan multiple repos for changes and generate git push commands. Checks: current project, .docs (secret), global Claude, global AHK."
disable-model-invocation: false
allowed-tools: Bash(git *), Glob
model: sonnet
---

# git-push-all

Scan multiple repositories for git changes and generate push commands for those with modifications.

## Repositories

<!-- CRITICAL: NEVER use absolute paths with usernames (C:\Users\ssv55\..., /c/Users/ssv55/...).
     Multiple developers share this skill — only the username differs between machines.
     Bash tool:  use $HOME, $PWD (shell resolves them at runtime).
     CMD output: use %USERPROFILE%, %CD% (CMD resolves them at runtime).
     Hardcoded D:\Data\... paths are OK ONLY when they contain no username component. -->

All paths use `$HOME` (bash) / `%USERPROFILE%` (CMD) — no hardcoded usernames.

| Alias | Bash path | CMD path | Notes |
|-------|-----------|----------|-------|
| **Project** | `$PWD` | current dir | Current working directory |
| **.docs** | `$PWD/.docs` | — | Secret folder with own git. **If absent or not a git repo — skip silently, NEVER mention** |
| **Claude** | `$HOME/.claude` | `%USERPROFILE%\.claude` | Global Claude config repo (symlink to D: drive) |
| **AHK** | `$HOME/Scripts` | `%USERPROFILE%\Scripts` | Global scripts & AutoHotKey repo |

## Execution

### Step 1: Check all repos in parallel

Run **all four** `git status --short` commands simultaneously (parallel Bash calls):

```bash
git -C "$PWD" status --short
```
```bash
git -C "$PWD/.docs" status --short 2>/dev/null
```
```bash
git -C "$HOME/.claude" status --short
```
```bash
git -C "$HOME/Scripts" status --short
```

For `.docs`: if the command fails or returns nothing — ignore silently. Do NOT mention `.docs` in output.

### Step 2: Get diffs for repos with changes

For each repo whose `git status --short` returned non-empty output, run `git diff` (parallel where possible):

```bash
git -C "<path>" diff
git -C "<path>" diff --cached
```

### Step 3: Generate output

For each repo with changes:

1. Compose a short commit message (3-5 words, English, prefix: `fix`/`add`/`update`/`refactor`/`remove`)
2. Output a command block with `cd /d` (Windows CMD syntax, `%USERPROFILE%` for user-relative paths)

**Format** — for each repo output a `###` header with alias, then a `cmd` code block:

    ### Claude

    ```cmd
    cd /d %USERPROFILE%\.claude && git add -A && git commit -m "update: memory and settings" && git pull --rebase && git push
    ```

    ### AHK

    ```cmd
    cd /d %USERPROFILE%\Scripts && git add -A && git commit -m "update: hook scripts" && git pull --rebase && git push
    ```

**Rules:**

- Only show repos that have changes — clean repos get no mention at all
- If ALL repos are clean: output `Все репозитории чистые, изменений нет.`
- `.docs` must NEVER appear in output if it doesn't exist, is not a git repo, or is clean. Other developers must not learn about it
- For **Project** use the real resolved project path in `cd /d` (get it from `$PWD` at runtime, convert to Windows backslash format)
- No extra text, explanations, or filler — just headers and command blocks
- Each command is a single line the user can copy-paste into CMD
