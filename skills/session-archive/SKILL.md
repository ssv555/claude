---
name: session-archive
description: Archive current session work to docs/archive/sessions/ with prompt, changes summary, and TODOs
disable-model-invocation: false
allowed-tools: AskUserQuestion,Bash(git *),Bash(mkdir *),Bash(head *),Bash(tail *),Bash(grep *),Bash(bun *),Bash(ls *),Read,Write,Glob,Grep
model: opus
---

Archive the current conversation session into a compact summary file in `docs/archive/sessions/`.

## Step 1: Gather all metadata (single batch)

Run **all commands in parallel** to collect metadata in one round-trip:

**Command A — Developer alias:**
`git config user.name 2>/dev/null || git config user.email 2>/dev/null | sed 's/@.*//'`

Apply mapping: `ssv555`/`ssv` → `ssv`, `Kirill`/`WhiteDullahan` → `kirill`.
Cyrillic → transliterate to Latin lowercase. No match → use lowercased as-is.
Empty → ask via AskUserQuestion: "Не удалось определить разработчика. Укажите алиас (например: ssv, kirill):"

**Command B — Session JSONL path:**
`ls -t ~/.claude/projects/*$(basename "$(pwd)")/*.jsonl 2>/dev/null | head -1`

**Command C — Git status:**
`git diff --stat HEAD 2>/dev/null; echo "---STATUS---"; git status --short 2>/dev/null`

**After resolving**: print `Developer: <alias> (from <source>)`.

## Step 2: Extract session data from JSONL

Using the JSONL path from Step 1, run **one combined command**:

```bash
F="<jsonl_path>" && \
head -1 "$F" | sed 's/.*"timestamp":"\([^"]*\)".*/\1/' && echo "---SEP---" && \
tail -1 "$F" | sed 's/.*"timestamp":"\([^"]*\)".*/\1/' && echo "---SEP---" && \
grep -m1 '"model":"' "$F" | sed 's/.*"model":"\([^"]*\)".*/\1/' && echo "---SEP---" && \
grep -m1 '"gitBranch"' "$F" | sed 's/.*"gitBranch":"\([^"]*\)".*/\1/'
```

This yields 4 values separated by `---SEP---`: start timestamp, end timestamp, model, gitBranch.

Then **one bun call** for date formatting and duration:
```
bun -e "const s=new Date('START'),e=new Date('END'),t=e-s;const h=Math.floor(t/36e5),m=Math.floor(t%36e5/6e4);const pad=n=>String(n).padStart(2,'0');const fmt=dt=>pad(dt.getDate())+'.'+pad(dt.getMonth()+1)+' '+pad(dt.getHours())+':'+pad(dt.getMinutes());const fn=s.getFullYear()+'.'+pad(s.getMonth()+1)+'.'+pad(s.getDate())+'_'+pad(s.getHours())+'.'+pad(s.getMinutes());console.log(fn+'|'+fmt(s)+'|'+fmt(e)+'|'+h+'h '+m+'m')"
```

Result: `2026.03.23_10.47|23.03 10:47|24.03 11:02|24h 15m` — split by `|` into: filename date, start display, end display, duration.

If JSONL extraction fails — still write the archive, just skip the metadata line.

## Step 3: Detect Repeated Invocation

Check if `/session-archive` was already called earlier in this conversation by searching conversation history for a previously written archive file path in `docs/archive/sessions/`.

**If this is a repeated call:**
- This is a **continuation archive** — only cover what happened AFTER the previous archive call
- The prompt = the user's first message after the previous archive (not the original session prompt)
- Topic = auto-generated from this new prompt
- "Выполнено" = only work done after the previous archive
- Metadata `Начало` = timestamp of the previous archive call (not session start)
- Create a new file with suffix `_2`, `_3`, etc. (based on how many archives exist for today + dev)

**If this is the first call:** proceed normally.

## Step 4: Analyze session & prepare content

From **conversation history** (already in context, no tool calls needed):

1. **Original prompt** — first substantive user request (or post-previous-archive if repeated). Short (<15 lines) → quote as-is. Long → summarize compactly.
2. **Spell-check prompt** — fix only typos/spelling/punctuation, never rephrase. If corrections found → show original vs corrected, list each change, ask via AskUserQuestion. No corrections → skip silently.
3. **Topic** — 2-3 words in English from the prompt (for filename).

**⛔ WAIT**: Steps 4-5 MUST NOT start until spell-check (step 2) is fully resolved — user approved or declined, or no corrections needed.

4. **What was done** — group by areas, not files. Use git status from Step 1. For repeated calls: only changes after previous archive.
5. **TODOs** — discussed but not completed.

## Step 5: Write archive file

Path: `docs/archive/sessions/<filename_date>_<dev>_<topic>.md`
Example: `docs/archive/sessions/2026.03.23_10.47_ssv_Home_pages.md`

Topic words separated by underscores (e.g. `Audit_columns_rules`).
If file already exists, append suffix: `_2`, `_3`, etc.
Ensure `docs/archive/sessions/` directory exists (`mkdir -p docs/archive/sessions`).

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

- **Компактность**: 1 строка на пункт. Сухо, по делу.
- **Группировка**: по фичам/областям, НЕ по файлам.
- **Русский язык** в содержимом файла.
- **Не спрашивать подтверждения** — сразу писать файл.
- **Промт**: близко к оригиналу, но компактно.
- **Тема файла**: 2-3 слова English, из промта.
- **Метаданные сессии**: всегда извлекать из JSONL и вставлять после промта.
- **Токены**: максимум параллельных вызовов, минимум раундтрипов. Данные из контекста — без лишних tool calls.
- After writing, print the full file path and a 1-line confirmation.
- Do NOT read files from `docs/archive/sessions/` — only write to it.
