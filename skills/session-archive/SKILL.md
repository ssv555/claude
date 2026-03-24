---
name: session-archive
description: Archive current session work to docs/archive/ with prompt, changes summary, and TODOs
disable-model-invocation: false
allowed-tools: AskUserQuestion,Bash(git *),Bash(date *),Bash(mkdir *),Bash(head *),Bash(tail *),Bash(python3 *),Bash(ls *),Bash(find *),Read,Write,Glob,Grep
model: sonnet
---

Archive the current conversation session into a compact summary file in `docs/archive/`.

## Input

No arguments required. Everything is auto-determined:
- **Topic**: auto-generated from the session prompt (2-3 words in English)
- **Developer**: from `git config user.name`
- **Date + time**: now
- **Session metadata**: from JSONL session file

## Step 1: Determine Developer Alias

Run `git config user.name` and apply mapping:
- `ssv555` → `ssv`
- `ssv` → `ssv`
- `Kirill` → `kirill`
- `WhiteDullahan` → `kirill`

If the name is in Cyrillic, transliterate to Latin lowercase (e.g. `Сергей` → `sergey`).
If no mapping match, use the git name lowercased as-is.
If git name is empty, ask via AskUserQuestion: "Не удалось определить разработчика. Укажите алиас (например: ssv, kirill):"

## Step 2: Get Date and Time

Run: `date "+%Y.%m.%d_%H.%M"`

This produces date and time for the filename, e.g. `2026.03.22_14.35`.

## Step 3: Extract Session Metadata from JSONL

Session JSONL files are stored at:
`~/.claude/projects/<project-hash>/<session-id>.jsonl`

To find the current session file:

```bash
# Find the project dir (matches current working directory path with dashes)
PROJECT_DIR=$(ls -d ~/.claude/projects/*VDole 2>/dev/null | head -1)

# Find the most recently modified JSONL file (= current session)
SESSION_FILE=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)
```

Extract metadata from the JSONL:

```bash
# First line → session start timestamp
START_TS=$(head -1 "$SESSION_FILE" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('timestamp','?'))")

# Last line → session end timestamp + model
END_DATA=$(tail -1 "$SESSION_FILE" | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
model=d.get('message',{}).get('model','?')
ts=d.get('timestamp', '?')
print(f'{model}|{ts}')
")

# Current branch
BRANCH=$(git branch --show-current)
```

Then compute:
- **Model**: from END_DATA (e.g. `claude-opus-4-6`)
- **Branch**: from git
- **Start time**: parse START_TS to local time `DD.MM HH:MM`
- **End time**: current time `DD.MM HH:MM`
- **Duration**: difference between end and start (e.g. `2h 15m`)

Format as a single metadata line:
```
**Model**: <model> | **Branch**: <branch> | **Начало**: <start> | **Конец**: <end> | **Длительность**: <duration>
```

If JSONL extraction fails — still write the archive, just skip the metadata line.

## Step 4: Detect Repeated Invocation

Check if `/session-archive` was already called earlier in this conversation by searching conversation history for a previously written archive file path in `docs/archive/`.

**If this is a repeated call:**
- This is a **continuation archive** — only cover what happened AFTER the previous archive call
- The prompt = the user's first message after the previous archive (not the original session prompt)
- Topic = auto-generated from this new prompt
- "Выполнено" = only work done after the previous archive
- Metadata `Начало` = timestamp of the previous archive call (not session start)
- Create a new file with suffix `_2`, `_3`, etc. (based on how many archives exist for today + dev)

**If this is the first call:** proceed normally.

## Step 5: Analyze Session

Review the conversation history (full if first call, or since last archive if repeated) to extract:

### 5a. Original Prompt
Find the first substantive task/request in the relevant scope.
- If short (<15 lines): quote as-is
- If long: summarize key points compactly, preserving the intent

### 5b. Auto-generate Topic
From the prompt, derive a **short topic** (2-3 words in English) that captures the main subject. This becomes part of the filename.
Examples: "Home page", "OAuth auth", "SEO optimization", "Deploy scripts"

### 5c. What Was Done
From the conversation context AND `git diff --stat` / `git status`, compile:
- Key features/changes implemented
- Architectural decisions made
- Group by logical areas, NOT by individual files
- For repeated calls: only include changes made after the previous archive

### 5d. Remaining TODOs
From the conversation — items discussed but not completed, known issues, next steps.

## Step 6: Write Archive File

Path: `docs/archive/<date>_<time>_<dev>_<topic>.md`
Example: `docs/archive/2026.03.22_14.35_ssv_Home_page.md`

Topic words separated by underscores (e.g. `Audit_columns_rules`).
If file already exists, append suffix: `_2`, `_3`, etc.
Ensure `docs/archive/` directory exists (`mkdir -p`).

### Template

```markdown
# PROMT

<original prompt or compact summary>

**Model**: <model> | **Branch**: <branch> | **Начало**: <start> | **Конец**: <end> | **Длительность**: <duration>

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
- **Метаданные сессии**: всегда извлекать из JSONL и вставлять после промта.
- After writing, print the full file path and a 1-line confirmation.
- Do NOT read files from `docs/archive/` — only write to it.
