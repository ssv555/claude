---
name: sealed
description: Manage sealed modules — protect critical security files from AI edits. Use when the user wants to seal/unseal file groups with /seal or /unseal commands, check sealed status, or add files to sealed groups.
allowed-tools: Bash(powershell *), Bash(git *), Read, Glob
model: haiku
---

# Sealed Modules Manager

Protects critical files (auth, security, payments) from accidental AI edits via a PreToolUse hook. The skill wraps `~/.claude/scripts/sealed-manage.ps1`.

## Registry layout

- Config folder: `~/.claude/sealed/` — one `sealed-<project>.json` per project
- Each file maps: `root` (absolute project path) → `groups` → `files`
- Hook `~/.claude/hooks/sealed-block.ps1` blocks Edit/Write on sealed files

## Commands

User invokes via `/seal` or `/unseal` (or natural language).

### `/seal` (no args) — show status

```bash
powershell -nop -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/sealed-manage.ps1" -Action list
```

Output the table verbatim. No extra commentary.

### `/seal <group>` — seal a group

```bash
powershell -nop -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/sealed-manage.ps1" -Action seal -Group "<group>"
```

Sets `sealed: true`, inserts `// @sealed` marker at line 1 of each file. Hook now blocks Edit/Write.

### `/unseal <group>` — temporarily unseal

```bash
powershell -nop -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/sealed-manage.ps1" -Action unseal -Group "<group>"
```

Sets `sealed: false`, removes markers. After edits, remind user to re-seal:
> Group `<group>` unsealed. Run `/seal <group>` when done editing.

### `/seal add <group> <file>` — add file to group

```bash
powershell -nop -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/sealed-manage.ps1" -Action add -Group "<group>" -Files "<file>"
```

File path must be relative to project root, forward slashes. Multiple files: comma-separated.

### `/seal remove <group> <file>` — remove file from group

```bash
powershell -nop -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/sealed-manage.ps1" -Action remove -Group "<group>" -Files "<file>"
```

### `/seal new <group> "<description>" <files>` — create new group

```bash
powershell -nop -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/sealed-manage.ps1" -Action new -Group "<group>" -Description "<description>" -Files "<file1>,<file2>"
```

Creates group with `sealed: false`. User must then run `/seal <group>` to activate.

## Rules

- Project is auto-detected via `git rev-parse --show-toplevel`
- Always show the script output verbatim — do NOT summarize or rephrase
- If script errors, show error as-is
- After `/unseal`, always remind to re-seal
- If user says "seal X" or "запечатай X" — treat as `/seal X`
- If user says "unseal X" or "распечатай X" — treat as `/unseal X`