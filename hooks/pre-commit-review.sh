#!/usr/bin/env bash
# pre-commit-review.sh — Auto code review on git commit
#
# Triggered by PreToolUse hook on Bash(git commit*).
# Flow: check gates → dialog (review/skip) → extract context → claude -p review → allow/deny
#
# Receives JSON on stdin with: session_id, transcript_path, tool_name, tool_input, cwd
#
# GATES (both must pass, otherwise skip silently):
#   1. File .claude/review-on-commit must exist in project root with "on" inside
#   2. Diff must contain code files (.ts, .tsx, .js, .jsx, .py, .go, .rs, .java, .pas)
#      Docs-only or config-only commits (.md, .json, .yml, .yaml, .toml, .css, .html) are skipped

set -euo pipefail

DIALOG="$HOME/.claude/scripts/dialog.ps1"
CODEX="$HOME/.claude/codex.md"

# ---- Read stdin JSON ----
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# ---- Gate 1: Check review-on-commit flag in .claude/user.conf ----
HOOKS_CONF="$CWD/.claude/user.conf"
if [ ! -f "$HOOKS_CONF" ]; then
  exit 0
fi

FLAG_VALUE=$(grep -i '^review-on-commit=' "$HOOKS_CONF" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [ "$FLAG_VALUE" != "on" ]; then
  exit 0
fi

# ---- Gate 2: Check if diff contains code files ----
STAGED_FILES=$(cd "$CWD" && git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED_FILES" ]; then
  STAGED_FILES=$(cd "$CWD" && git diff HEAD --name-only 2>/dev/null)
fi

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
  # Docs/config only — skip review
  exit 0
fi

# ---- Step 1: Dialog — ask user ----
CHOICE=$(powershell -nop -f "$DIALOG" \
  -Mode custom \
  -Title "Code Review" \
  -Agent "Pre-Commit" \
  -Message "Запустить code review перед коммитом?" \
  -Options "review:Code Review,skip:Пропустить")

if [ "$CHOICE" != "review" ]; then
  exit 0
fi

# ---- Step 2: Get staged diff ----
DIFF=$(cd "$CWD" && git diff --cached 2>/dev/null)
if [ -z "$DIFF" ]; then
  DIFF=$(cd "$CWD" && git diff HEAD 2>/dev/null)
fi

if [ -z "$DIFF" ]; then
  exit 0
fi

# ---- Step 3: Extract session context from transcript ----
CONTEXT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  CONTEXT=$(tail -20 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r 'select(.type == "assistant" or .type == "human") | .message // .content // empty' 2>/dev/null | tail -2000)
fi

# ---- Step 4: Save diff + context to temp files ----
TMPDIR=$(mktemp -d)
echo "$DIFF" > "$TMPDIR/diff.txt"
echo "$CONTEXT" > "$TMPDIR/context.txt"

# ---- Step 5: Run code review via claude -p ----
REVIEW_PROMPT="You are a code reviewer. Read the codex rules from ~/.claude/codex.md.

SESSION CONTEXT (what the developer was working on):
$(head -c 3000 "$TMPDIR/context.txt")

GIT DIFF to review:
$(head -c 10000 "$TMPDIR/diff.txt")

Review the diff against ALL codex rules. Focus on changes only, not pre-existing code.
Classify findings as P0 (critical), P1 (major), P2 (minor), P3 (suggestion).
Consider the session context — don't flag intentionally incomplete work if the context explains it.

Output format:
- If no P0/P1 issues: exactly 'APPROVE' on the first line
- If P0/P1 issues found: 'DENY' on the first line, then list each issue

Be strict on security, correctness, data integrity. Be lenient on style."

RESULT=$(echo "$REVIEW_PROMPT" | claude -p --model sonnet 2>/dev/null || echo "ERROR")

# Clean up temp files
rm -rf "$TMPDIR"

# ---- Step 6: Parse result ----
FIRST_LINE=$(echo "$RESULT" | head -1)

if echo "$FIRST_LINE" | grep -qi "APPROVE"; then
  exit 0
fi

if echo "$FIRST_LINE" | grep -qi "DENY\|ERROR"; then
  FINDINGS=$(echo "$RESULT" | tail -n +2 | head -30)

  powershell -nop -f "$DIALOG" \
    -Mode simple \
    -Title "Code Review — Issues Found" \
    -Agent "Pre-Commit" \
    -Message "$FINDINGS" \
    -Buttons OK \
    -Icon Warning > /dev/null 2>&1

  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Code review found P0/P1 issues. Fix before committing."}}'
  exit 0
fi

# Fallback — allow if result is unclear
exit 0
