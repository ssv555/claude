---
name: session-archive
description: Archive current session work to docs/archive/ with prompt, changes summary, and TODOs
disable-model-invocation: false
allowed-tools: AskUserQuestion,Bash(git *),Bash(date *),Bash(mkdir *),Read,Write,Glob,Grep
model: sonnet
---

Archive the current conversation session into a compact summary file in `docs/archive/`.

## Input

No arguments required. Everything is auto-determined:
- **Topic**: auto-generated from the session prompt (2-3 words in English)
- **Developer**: from `git config user.name`
- **Date + time**: now

## Step 1: Determine Developer Alias

Run `git config user.name` and apply mapping:
- `ssv555` → `ssv`
- `Kirill` → `kirill`
- `WhiteDullahan` → `kirill`

If the name is in Cyrillic, transliterate to Latin lowercase (e.g. `Сергей` → `sergey`).
If no mapping match, use the git name lowercased as-is.
If git name is empty, ask via AskUserQuestion: "Не удалось определить разработчика. Укажите алиас (например: ssv, kirill):"

## Step 2: Get Date and Time

Run: `date "+%Y.%m.%d - %H.%M"`

This produces date and time for the filename, e.g. `2026.03.22 - 14.35`.

## Step 3: Analyze Session

Review the **full conversation history above this skill invocation** to extract:

### 3a. Original Prompt
Find the first substantive task/request the user gave Claude in this session.
- If short (<15 lines): quote as-is
- If long: summarize key points compactly, preserving the intent

### 3b. Auto-generate Topic
From the original prompt, derive a **short topic** (2-3 words in English) that captures the main subject of the session. This becomes part of the filename.
Examples: "Home page", "OAuth auth", "SEO optimization", "Deploy scripts"

### 3c. What Was Done
From the conversation context AND `git diff --stat` / `git status`, compile:
- Key features/changes implemented
- Architectural decisions made
- Group by logical areas, NOT by individual files

### 3d. Remaining TODOs
From the conversation — items discussed but not completed, known issues, next steps.

## Step 4: Write Archive File

Path: `docs/archive/<date> - <time> - <dev> - <topic>.md`
Example: `docs/archive/2026.03.22 - 14.35 - ssv - Home page.md`

If file already exists, append suffix: ` (2)`, ` (3)`, etc.
Ensure `docs/archive/` directory exists (`mkdir -p`).

### Template

```markdown
# PROMT

<original prompt or compact summary>

## Выполнено

<grouped bullet list — 1 line per bullet, grouped by area>

### Модифицированные файлы

- <file> — <brief what changed>

### Созданные файлы

- <file> — <brief purpose>

---

## TODO

- <remaining items, or "Нет">
```

## Rules

- **Компактность**: каждый пункт — 1 строка. Без деталей реализации. Сухо, по делу.
- **Группировка**: по фичам/областям, НЕ по файлам.
- **Русский язык** в содержимом файла.
- **Не спрашивать подтверждения** — сразу писать файл.
- **Промт**: сохранять максимально близко к оригиналу, но компактно.
- **Тема файла**: генерировать автоматически из промта, 2-3 слова, коротко и ёмко.
- After writing, print the full file path and a 1-line confirmation.
- Do NOT read files from `docs/archive/` — only write to it.
