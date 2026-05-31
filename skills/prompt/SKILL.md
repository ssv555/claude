---
name: prompt
description: Manage prompt optimizer hook (on/off, min-words)
model: sonnet
context: fork
---

# Prompt Optimizer Control

## Instructions

1. Read the state file: `~/.claude/prompt-optimizer-state.json`
   - If missing, defaults are: `{ "enabled": true, "minWords": 10 }`
2. Use `AskUserQuestion` to ask the user what to do.
   Show current status in the question text: "Prompt optimizer: [ON/OFF], min words: [N]. What to do?"
   Options:
   - "Enable" (if currently disabled)
   - "Disable" (if currently enabled)
   - "Min words" — change the minimum word threshold
   - "Edit prompts" — open system prompts file for editing
3. If user chose "Edit prompts":
   - Ask which prompt to edit via AskUserQuestion: "Which prompt to edit?" Options: "Optimize", "Echo", "Both"
   - Open selected file(s) in Cursor via Bash:
     - Optimize: `"$LOCALAPPDATA/Programs/Cursor/resources/app/bin/cursor.cmd" "$USERPROFILE/.claude/hooks/prompt-optimize.txt"`
     - Echo: `"$LOCALAPPDATA/Programs/Cursor/resources/app/bin/cursor.cmd" "$USERPROFILE/.claude/hooks/prompt-echo.txt"`
     - Both: open both files in one command
   - Tell user: "File opened in editor. Changes take effect on next prompt."
   - Done (no state file changes needed)
4. If user chose "Min words", ask a follow-up question:
   "Minimum words to trigger optimization (current: [N])?"
   Options: "5", "10", "15", "20" (user can also type custom via Other)
5. Write the updated state to `~/.claude/prompt-optimizer-state.json`:
   ```json
   {
     "enabled": true,
     "minWords": 10
   }
   ```
6. Confirm the change to the user in one line.

## Rules

- State file path: `~/.claude/prompt-optimizer-state.json`
- Only modify the state file, nothing else
- Do NOT modify settings.json or hook scripts
- Keep responses concise
