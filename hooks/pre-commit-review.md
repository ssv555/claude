# pre-commit-review — Auto Code Review on Commit

Auto code review via `claude -p` triggered by git pre-commit hook.
Fires only when Claude Code is running, project opted in, and diff contains code files.

## Architecture

```
git commit (any terminal: CMD, PowerShell, Git Bash, Cursor terminal)
  → .git/hooks/pre-commit                    (per-project trigger, 1 line)
    → ~/.claude/hooks/pre-commit-review.sh    (global logic, single source)
      Gates:
        1. Claude Code active? (recent transcript)
        2. .claude/user.conf → review-on-commit=on?
        3. Code files in diff?
      If all gates pass:
        → toast: "Pre-commit hook: N files"
        → dialog.ps1: Code Review + Коммит / Только коммит / Отменить всё
        → claude -p + codex.md (AI review)
        → toast: result (APPROVE / DENY)
        → log opens in Cursor
        → .tmp/code-review-log/<datetime>.log.md
```

## Files

| File | Location | Purpose |
|------|----------|---------|
| `pre-commit-review.sh` | `~/.claude/hooks/` | Global review script. Edit once — works everywhere |
| `pre-commit-review.md` | `~/.claude/hooks/` | This instruction file |
| `pre-commit` | `.git/hooks/` per project | Trigger (1 line, calls the global script) |
| `user.conf` | `.claude/` per project | Config flags (review-on-commit=on/off) |
| `dialog.ps1` | `~/.claude/scripts/` | GUI dialogs with buttons |
| `toast.ps1` | `~/.claude/scripts/` | Auto-closing notification with countdown |
| `codex.md` | `~/.claude/` | Engineering rules the reviewer checks against |

## Setup for a New Project

### 1. Create git hook trigger

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# → ~/.claude/hooks/pre-commit-review.sh
bash ~/.claude/hooks/pre-commit-review.sh
EOF
chmod +x .git/hooks/pre-commit
```

### 2. Create config file

```bash
mkdir -p .claude
cat > .claude/user.conf << 'EOF'
# Auto code review via claude -p on every git commit.
# on = show dialog before commit, run review if confirmed.
# off / missing file / missing key = skip review silently.
review-on-commit=on
EOF
```

### 3. Verify dependencies

```bash
claude --version   # Claude Code CLI
jq --version       # JSON parsing
powershell -nop -c "echo ok"   # GUI dialogs
```

## Gates (all must pass, otherwise silent skip with toast)

1. **Claude Code active** — recent transcript file exists for this project (< 10 min)
2. **review-on-commit=on** — flag in `.claude/user.conf`
3. **Code files in diff** — `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.rs`, `.java`, `.pas`, `.sh`, `.ps1`

If any gate fails — toast shows reason, commit proceeds without review.

## Dialog: 3 Buttons

| Button | Action | Exit code |
|--------|--------|-----------|
| **Code Review + Коммит** | Run review → APPROVE=commit, DENY=block | 0 or 1 |
| **Только коммит** | Skip review, commit immediately | 0 |
| **Отменить всё** | No commit, no review | 1 |

## Toast Notifications

Auto-closing dialogs with countdown (fire-and-forget, non-blocking):
- Hook started: "Pre-commit hook: N файлов с кодом"
- User choice: "Коммит без ревью" / "Коммит отменён"
- Review started: "Запускаю ревью..."
- Review result: "APPROVE — N файлов, Xs" / "DENY — P0:N P1:N"

## Log Files

Location: `.tmp/code-review-log/<YYYY-MM-DD_HH-MM-SS>.log.md`

Contains:
- Commit message
- Files reviewed (clickable markdown links)
- Time elapsed
- Verdict (APPROVE/DENY)
- Full review result

Log auto-opens in Cursor after review.

`.tmp/` must be in `.gitignore` (not committed).

## Disable/Enable

```ini
# .claude/user.conf
review-on-commit=off    # disable
review-on-commit=on     # enable
```

Or delete `.claude/user.conf` — review won't trigger.

## How It Works

1. `git commit` fires `.git/hooks/pre-commit`
2. Hook calls `~/.claude/hooks/pre-commit-review.sh`
3. Script checks 3 gates (toast notification if skipped)
4. If passed — toast + dialog with 3 buttons
5. **Code Review + Коммит:**
   - Extracts session context from Claude Code transcript
   - Gets staged diff
   - Sends both to `claude -p --model sonnet` with codex rules
   - Logs result to `.tmp/code-review-log/`
   - Opens log in Cursor
   - APPROVE → toast + commit proceeds (exit 0)
   - DENY → toast + findings dialog + commit blocked (exit 1)
6. **Только коммит** → toast + commit proceeds (exit 0)
7. **Отменить всё** → toast + commit blocked (exit 1)

## Dependencies

- `claude` CLI (Claude Code)
- `jq` (JSON parsing)
- `powershell` (GUI dialogs + toasts)
- `git`
