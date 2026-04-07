#!/usr/bin/env bash
# pre-commit-review.sh — Auto code review on git commit
#
# Called from: .git/hooks/pre-commit (per-project symlink/one-liner)
# Config:     .claude/user.conf (per-project, review-on-commit=on/off)
# Dialog:     ~/.claude/scripts/dialog.ps1
# Toast:      ~/.claude/scripts/toast.ps1
# Rules:      ~/.claude/codex.md
# Context:    ~/.claude/projects/<encoded-cwd>/*.jsonl (active Claude Code session)
# Logs:       .tmp/code-review-log/<datetime>.log.md (per-project)
#
# GATES (all must pass, otherwise skip with toast):
#   1. Claude Code is running (recent transcript exists)
#   2. review-on-commit=on in .claude/user.conf
#   3. Diff contains code files (.ts, .tsx, .js, .jsx, .py, .go, .rs, .java, .pas, .sh, .ps1)
#
# Exit codes: 0 = allow commit, 1 = block commit

# NOTE: no "set -e", no "set -u", no "pipefail" — git hooks must never crash silently.
# Any unexpected error = allow commit (fail open, not fail closed).

DIALOG="$HOME/.claude/scripts/dialog.ps1"
TOAST="$HOME/.claude/scripts/toast.ps1"
CODEX="$HOME/.claude/codex.md"
CWD=$(pwd)
START_TIME=$(date +%s)

# ---- Helper: toast — fire and forget (non-blocking) ----
toast() {
  local icon="${1:-info}" title="${2:-Code Review}" msg="${3:-}" sec="${4:-4}"
  powershell.exe -nop -f "$TOAST" -Title "$title" -Agent "Pre-Commit" -Message "$msg" -Icon "$icon" -Seconds "$sec" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ---- Helper: copy fix prompt to clipboard ----
copy_fix_prompt() {
  local log_rel=".tmp/code-review-log/$(basename "$LOG_FILE")"
  powershell.exe -nop -c "Set-Clipboard \"Исправь замечания code review по правилам codex (~/.claude/codex.md). Лог замечаний: $log_rel\"" 2>/dev/null || true
}

# ---- Helper: toast_wait — blocking (waits for countdown or OK click) ----
toast_wait() {
  local icon="${1:-info}" title="${2:-Code Review}" msg="${3:-}" sec="${4:-4}"
  powershell.exe -nop -f "$TOAST" -Title "$title" -Agent "Pre-Commit" -Message "$msg" -Icon "$icon" -Seconds "$sec" 2>/dev/null || true
}

# ---- Gate 1: Check if Claude Code is running (fresh transcript < 10 min) ----
PROJECTS_DIR="$HOME/.claude/projects"
TRANSCRIPT=""

if [ -d "$PROJECTS_DIR" ]; then
  ENCODED_CWD=$(echo "$CWD" | sed 's|^/\([a-zA-Z]\)/|\1--|' | sed 's|/|-|g')
  PROJECT_DIR="$PROJECTS_DIR/$ENCODED_CWD"

  if [ -d "$PROJECT_DIR" ]; then
    TRANSCRIPT=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.jsonl" -mmin -10 2>/dev/null | head -1)
  fi
fi

if [ -z "$TRANSCRIPT" ]; then
  toast "info" "Code Review" "Пропущен: Claude Code не активен"
  exit 0
fi

# ---- Gate 2: Check review-on-commit flag in .claude/user.conf ----
USER_CONF="$CWD/.claude/user.conf"
if [ ! -f "$USER_CONF" ]; then
  toast "info" "Code Review" "Пропущен: нет .claude/user.conf"
  exit 0
fi

FLAG_VALUE=$(grep -i '^review-on-commit=' "$USER_CONF" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [ "$FLAG_VALUE" != "on" ]; then
  toast "info" "Code Review" "Пропущен: review-on-commit=off"
  exit 0
fi

# ---- Gate 3: Check if diff contains code files ----
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED_FILES" ]; then
  toast "info" "Code Review" "Пропущен: нет staged файлов"
  exit 0
fi

FILE_COUNT=$(echo "$STAGED_FILES" | wc -l | tr -d ' ')
HAS_CODE=false
while IFS= read -r file; do
  case "$file" in
    *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.java|*.pas|*.sh|*.ps1)
      HAS_CODE=true
      break
      ;;
  esac
done <<< "$STAGED_FILES"

if [ "$HAS_CODE" != "true" ]; then
  toast "info" "Code Review" "Пропущен: нет кодовых файлов ($FILE_COUNT файлов — только docs/config)"
  exit 0
fi

toast "info" "Code Review" "Pre-commit hook: $FILE_COUNT файлов с кодом"

# ---- Step 1: Dialog — ask user ----
CHOICE=$(powershell -nop -f "$DIALOG" \
  -Mode custom \
  -Title "Code Review" \
  -Agent "Pre-Commit" \
  -Message "Коммит: $FILE_COUNT файлов. Что делать?" \
  -Options "review:Code Review + Коммит,commit:Только коммит,cancel:Отменить всё")

if [ "$CHOICE" = "cancel" ] || [ -z "$CHOICE" ]; then
  toast "info" "Code Review" "Коммит отменён пользователем" || true
  exit 1
fi

if [ "$CHOICE" = "commit" ]; then
  toast "info" "Code Review" "Коммит без ревью" || true
  exit 0
fi

# ---- Step 2: Get staged diff ----
DIFF=$(git diff --cached 2>/dev/null)
if [ -z "$DIFF" ]; then
  exit 0
fi

DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

# ---- Step 3: Extract session context from transcript ----
CONTEXT=""
if [ -f "$TRANSCRIPT" ]; then
  CONTEXT=$(tail -20 "$TRANSCRIPT" 2>/dev/null | jq -r 'select(.type == "assistant" or .type == "human") | .message // .content // empty' 2>/dev/null | tail -c 3000)
fi

# ---- Step 4: Run code review via claude -p ----
TMPDIR=$(mktemp -d)
echo "$DIFF" > "$TMPDIR/diff.txt"

REVIEW_PROMPT="You are a code reviewer. Read the codex rules from ~/.claude/codex.md.

SESSION CONTEXT (what the developer was working on):
$CONTEXT

GIT DIFF to review:
$(head -c 10000 "$TMPDIR/diff.txt")

Review the diff against ALL codex rules. Focus on changes only, not pre-existing code.
Classify findings as P0 (critical), P1 (major), P2 (minor), P3 (suggestion).
Consider the session context — don't flag intentionally incomplete work if the context explains it.

Output format (first line MUST be one of these three words):
- APPROVE — no issues at all, or only trivial nitpicks not worth mentioning
- WARN — no P0/P1, but has P2/P3 findings worth noting. List them after WARN line.
- DENY — has P0 or P1 issues. List each issue with file:line after DENY line.

Be strict on security, correctness, data integrity. Be lenient on style."

toast "info" "Code Review" "Запускаю ревью... ($FILE_COUNT файлов, $DIFF_LINES строк)"

RESULT=$(echo "$REVIEW_PROMPT" | claude -p --model sonnet 2>"$TMPDIR/stderr.txt" || true)

if [ -z "$RESULT" ]; then
  STDERR=$(cat "$TMPDIR/stderr.txt" 2>/dev/null)
  RESULT="ERROR: claude -p returned empty. stderr: $STDERR"
fi

rm -rf "$TMPDIR"

# ---- Step 5: Calculate time ----
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ---- Step 6: Log result ----
LOG_DIR="$CWD/.tmp/code-review-log"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d_%H-%M-%S').log.md"
COMMIT_MSG=$(git log --format=%s -1 2>/dev/null || echo "pending commit")

# Build clickable file links (relative from .tmp/code-review-log/ to project root = ../../)
LINKED_FILES=""
while IFS= read -r f; do
  [ -n "$f" ] && LINKED_FILES="$LINKED_FILES
- [$f](../../$f)"
done <<< "$STAGED_FILES"

cat > "$LOG_FILE" << LOGEOF
# Code Review — $(date '+%Y-%m-%d %H:%M:%S')

- **Commit:** $COMMIT_MSG
- **Files:** $FILE_COUNT ($DIFF_LINES lines diff)
- **Time:** ${ELAPSED}s
- **Verdict:** $(echo "$RESULT" | head -1)

## Files Reviewed
$LINKED_FILES

## Review Result

$RESULT
LOGEOF

# Open log in Cursor IDE
WIN_LOG=$(echo "$LOG_FILE" | sed 's|^/\([a-zA-Z]\)/|\1:\\|' | sed 's|/|\\|g')
"$LOCALAPPDATA/Programs/Cursor/resources/app/bin/cursor.cmd" "$WIN_LOG" 2>/dev/null

# ---- Step 7: Parse result and notify ----
FIRST_LINE=$(echo "$RESULT" | head -1)

# --- APPROVE: clean, commit proceeds ---
if echo "$FIRST_LINE" | grep -qi "APPROVE"; then
  toast "success" "Code Review" "APPROVE — $FILE_COUNT файлов, ${ELAPSED}s"
  exit 0
fi

# --- WARN: P2/P3 only, ask user ---
if echo "$FIRST_LINE" | grep -qi "WARN"; then
  toast "warning" "Code Review" "Есть замечания P2/P3, ${ELAPSED}s"

  LOG_REL=".tmp/code-review-log/$(basename "$LOG_FILE")"
  FIX_PROMPT="Исправь замечания code review по правилам codex (~/.claude/codex.md). Лог замечаний: $LOG_REL"

  CHOICE=$(powershell -nop -f "$DIALOG" \
    -Mode custom \
    -Title "Code Review — Замечания" \
    -Agent "Pre-Commit" \
    -Message "Есть мелкие замечания (P2/P3). Коммитить?" \
    -Options "commit:Коммитить,cancel:Отменить и исправить" \
    -Footer "При отмене в буфер скопируется: $FIX_PROMPT")

  if [ "$CHOICE" = "commit" ]; then
    toast "info" "Code Review" "Коммит с замечаниями P2/P3"
    exit 0
  else
    copy_fix_prompt
    toast "info" "Code Review" "Коммит отменён. Промпт скопирован — Ctrl+V в Claude Code"
    exit 1
  fi
fi

# --- DENY: P0/P1, block commit ---
if echo "$FIRST_LINE" | grep -qi "DENY\|ERROR"; then
  P0_COUNT=$(echo "$RESULT" | grep -ci "P0" || true)
  P1_COUNT=$(echo "$RESULT" | grep -ci "P1" || true)

  toast "error" "Code Review" "DENY — P0:$P0_COUNT P1:$P1_COUNT, ${ELAPSED}s"

  copy_fix_prompt

  LOG_REL=".tmp/code-review-log/$(basename "$LOG_FILE")"
  FIX_PROMPT="Исправь замечания code review по правилам codex (~/.claude/codex.md). Лог замечаний: $LOG_REL"

  powershell -nop -f "$DIALOG" \
    -Mode custom \
    -Title "Code Review — Критические ошибки" \
    -Agent "Pre-Commit" \
    -Message "Коммит заблокирован. P0:$P0_COUNT P1:$P1_COUNT. Промпт скопирован — Ctrl+V в Claude Code." \
    -Options "ok:OK" \
    -Footer "В буфере: $FIX_PROMPT" > /dev/null 2>&1

  exit 1
fi

# --- Fallback: unclear result, ask user ---
toast "warning" "Code Review" "Неопределённый результат, ${ELAPSED}s"

CHOICE=$(powershell -nop -f "$DIALOG" \
  -Mode custom \
  -Title "Code Review — Неопределённый результат" \
  -Agent "Pre-Commit" \
  -Message "Ревью вернул неясный результат. Коммитить?" \
  -Options "commit:Коммитить,cancel:Отменить")

if [ "$CHOICE" = "commit" ]; then
  exit 0
else
  exit 1
fi
