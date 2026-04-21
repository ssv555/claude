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
`grep '^DEV_SHORT_NAME=' .env.development 2>/dev/null | cut -d'=' -f2-`
Fallback (if empty): `git config user.name 2>/dev/null || git config user.email 2>/dev/null | sed 's/@.*//'`
Apply mapping to fallback only: `ssv555`/`ssv` → `ssv`, `Kirill`/`WhiteDullahan` → `kirill`.
Cyrillic → transliterate to Latin lowercase. No match → use lowercased as-is.
Empty after all attempts → ask via AskUserQuestion: "Не удалось определить разработчика. Укажите алиас (например: ssv, kirill):"

**Command B — Session JSONL path + session ID:**
`SESSION_JSONL=$(ls -t ~/.claude/projects/*$(basename "$(pwd)")/*.jsonl 2>/dev/null | head -1) && echo "$SESSION_JSONL" && echo "---SID---" && basename "$SESSION_JSONL" .jsonl`

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

## Step 2.5: Collect token usage from JSONL

Using the JSONL path and SESSION_ID from Step 1, run **one bun command** to aggregate tokens from main session + all subagents:

```bash
bun -e "
const fs=require('fs');
const sid='SESSION_ID';
const main='SESSION_JSONL_PATH';
const subDir=main.replace('.jsonl','')+'/subagents';
function sum(f){const ls=fs.readFileSync(f,'utf-8').split('\n').filter(Boolean);let i=0,cc=0,cr=0,o=0,n=0;for(const l of ls){try{const j=JSON.parse(l);if(j.message?.usage){const u=j.message.usage;i+=u.input_tokens||0;cc+=u.cache_creation_input_tokens||0;cr+=u.cache_read_input_tokens||0;o+=u.output_tokens||0;n++}}catch{}}return{messages:n,input:i,cache_create:cc,cache_read:cr,output:o,total:i+cc+cr+o}}
const m=sum(main);const subs=[];
try{const files=fs.readdirSync(subDir).filter(f=>f.endsWith('.jsonl'));for(const f of files){subs.push({file:f,...sum(subDir+'/'+f)})}}catch{}
const grand={input:m.input,cache_create:m.cache_create,cache_read:m.cache_read,output:m.output,total:m.total};
for(const s of subs){grand.input+=s.input;grand.cache_create+=s.cache_create;grand.cache_read+=s.cache_read;grand.output+=s.output;grand.total+=s.total}
console.log(JSON.stringify({main:m,subagents:subs,grand}))
"
```

Replace `SESSION_ID` and `SESSION_JSONL_PATH` with actual values from Step 1. Parse the JSON output → use `grand.total` for the archive summary line. If the command fails, write `Токены: n/a`.

## Step 2.7: Compute relative links to session JSONL files

The archive file lives at `docs/archive/sessions/<name>.md` (inside the workspace). The session JSONL and its subagent JSONLs live outside the workspace (typically under `C:\Users\<user>\.claude\projects\...`). Compute **forward-slash relative paths from the archive file's directory** to each JSONL so the links open as clickable files in VSCode.

Use one bun command (paths from Step 1 + the archive file path from Step 5):

```bash
bun -e "
const path=require('path');const fs=require('fs');
const archiveDir=path.resolve('docs/archive/sessions');
const main='SESSION_JSONL_PATH';
const subDir=main.replace(/\.jsonl$/,'')+'/subagents';
const rel=p=>path.relative(archiveDir,p).split(path.sep).join('/');
const out={main:rel(main),subs:[]};
try{const files=fs.readdirSync(subDir).filter(f=>f.endsWith('.jsonl'));for(const f of files){out.subs.push({name:f,path:rel(subDir+'/'+f)})}}catch{}
console.log(JSON.stringify(out))
"
```

Replace `SESSION_JSONL_PATH` with the actual path from Step 1. Parse JSON → `out.main` is the relative path to the main session JSONL; `out.subs[]` lists subagent JSONLs (may be empty).

If the bun call fails, skip the "Сессия" block entirely — do not write absolute paths as fallback.

## Step 3: Detect Repeated Invocation

Check if `/session-archive` was already called earlier in this conversation by searching conversation history for a previously written archive file path in `docs/archive/sessions/`.

**CRITICAL — no exceptions:** If `/session-archive` has EVER been called earlier in this conversation, this is a **continuation archive** regardless of how different the new topic or work is. You are NOT creating two "first" archives in one conversation. Same JSONL → continuations. Never skip the suffix because "the topic is unrelated" — `/changelog-sync` segments the JSONL by the `_N` suffix; omitting it causes two .md files to claim the same JSONL timeline and double-count work time.

**If this is a repeated call:**
- This is a **continuation archive** — only cover what happened AFTER the previous archive call
- The prompt = the user's first message after the previous archive (not the original session prompt)
- Topic = auto-generated from this new prompt (new work, new topic is fine)
- "Выполнено" = only work done after the previous archive
- Metadata `Начало` = timestamp of the previous archive call (not session start)
- Metadata `Конец` = current timestamp (when this archive is being written)
- Filename MUST have suffix `_2`, `_3`, etc. — count how many archives exist for today + dev so far, add 1. The topic in the filename can be completely different from the first archive's topic.

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
Suffix `_2`, `_3`, etc. is REQUIRED for continuation archives (see Step 3) — even when the topic is new — and also whenever a same-timestamp file already exists on disk.
Ensure `docs/archive/sessions/` directory exists (`mkdir -p docs/archive/sessions`).

### Template

```markdown
# PROMT

<original prompt or compact summary>

**Model**: <model> | **Branch**: <branch> | **Начало**: <start> | **Конец**: <end> | **Длительность**: <duration> | **Токены**: <grand.total> (in: <input>, cache_create: <cache_create>, cache_read: <cache_read>, out: <output>)

**Сессия**: [<sessionId>.jsonl](<out.main>)<if out.subs not empty:> · субагенты: [<sub1.name>](<sub1.path>), [<sub2.name>](<sub2.path>), ...

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
- After writing, print the file path as a clickable markdown link: `[filename.md](relative/path/filename.md)` and a 1-line confirmation.
- Do NOT read files from `docs/archive/sessions/` — only write to it.
