---
name: open
description: Open file(s) in editor
disable-model-invocation: true
model: haiku
context: fork
---

Open specified file(s) in Cursor IDE editor.

User provides file path(s) as arguments. Open files using Cursor command line tool.

**Command:**
```bash
"$LOCALAPPDATA/Programs/Cursor/resources/app/bin/cursor.cmd" "D:\full\path\to\file1" 
"D:\full\path\to\file2"
```

**Rules:**
- ALWAYS use FULL absolute paths (never relative paths)
- Convert all paths to Windows format (D:\path\to\file)
- Multiple files can be opened in single command
- Expand glob patterns (like ~/.claude/skills/*/SKILL.md) before passing to cursor.cmd

**Examples:**
- `/open ~/.claude/skills/git-push/SKILL.md` → opens single skill file
- `/open file1.txt file2.md` → opens multiple files
