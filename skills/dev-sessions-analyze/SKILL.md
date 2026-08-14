---
name: dev-sessions-analyze
description: Chief-only — score a dev's Claude Code session on AI-usage quality and engagement. Lists sessions; chief picks one; analyzes the JSONL against 10 quality dimensions and writes a recommendation report. Use when user says "/dev-sessions-analyze <alias>", "проанализируй сессии <alias>", "оцени работу <alias>".
model: opus
allowed-tools: Bash(*), Read(*), Write(*), Grep(*), Glob(*), Agent(*)
---

# dev-sessions-analyze

Анализ Claude Code сессий разработчика. **Только шеф (ssv555 / PC).**

## Status block

```
SKILL:  dev-sessions-analyze
MODEL:  opus
```

## Chief-identity guard

```powershell
if (-not (($env:USERNAME -eq 'ssv555') -or ($env:COMPUTERNAME -eq 'PC-SKY'))) {
    Write-Error "Forbidden: chief-only skill"
    exit 1
}
```

## Аргумент

`/dev-sessions-analyze <alias>` — alias разработчика.

Без аргумента → перечислить всех в группе `developers` через `ssh moscow_my "getent group developers"`, спросить какого.

## Constants

```
DEV_HOME             = /home/<alias>
SESSIONS_GLOB        = ${DEV_HOME}/.claude/projects/*/*.jsonl
TOPICS_CACHE         = C:\Users\ssv55\.claude\developers\<alias>\topics.json
REPORTS_DIR          = D:\Data\Documents\Programming\Projects\WEB\VDole\.docs\dev\sessions
REPORT_NAME          = <alias>_<YYYY-MM-DD>_<sid_short>.md      (sid_short = first 8 chars of sessionId)
LARGE_THRESHOLD      = 5 MB   (above → split via subagents)
ACTIVE_TIME_GAP_CAP  = 5 min  (gaps >5 min between user msgs count as 5 min only)
```

## Алгоритм

### Шаг 1 — Discovery

```bash
ssh moscow_my "sudo find /home/<alias>/.claude/projects -name '*.jsonl' -printf '%p|%s|%T@\n' 2>/dev/null"
```

Для каждой JSONL получи:
- `path` (полный путь на сервере)
- `size` (байты)
- `mtime` (epoch)
- `sessionId` (basename без `.jsonl`)

Если файлов нет → «у <alias> нет сессий — возможно дев ещё не запускал claude». Стоп.

### Шаг 2 — Метаданные каждой сессии

Для каждой JSONL — quick scan через ssh+jq:

```bash
ssh moscow_my "sudo cat <path> | jq -s '{
  msg_count: length,
  user_msgs: ([.[] | select(.type==\"user\")] | length),
  assistant_msgs: ([.[] | select(.type==\"assistant\")] | length),
  tool_calls: ([.[] | select(.message.content?[]?.type==\"tool_use\")] | length),
  tokens_in: ([.[] | select(.message.usage) | .message.usage.input_tokens] | add // 0),
  tokens_cache: ([.[] | select(.message.usage) | (.message.usage.cache_creation_input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0)] | add // 0),
  tokens_out: ([.[] | select(.message.usage) | .message.usage.output_tokens] | add // 0),
  first_ts: ([.[] | .timestamp // empty] | first),
  last_ts:  ([.[] | .timestamp // empty] | last)
}'"
```

### Шаг 3 — Topic generation (4-5 слов)

Кеш `~/.claude/developers/<alias>/topics.json` (формат: `{sessionId: "topic text"}`). Для сессий БЕЗ topic в кеше:
1. Pull первые 3-5 user-сообщений из JSONL (через `ssh moscow_my "sudo cat ... | jq '[.[] | select(.type==\"user\") | .message.content] | .[0:5]'"`)
2. Спросить **haiku** (через Agent с `model: 'haiku'`): «Опиши тему этой сессии в 4-5 словах на русском, без кавычек, без точки в конце. Контекст: первые сообщения пользователя:\n<контент>»
3. Сохранить в `topics.json`

### Шаг 4 — Проверка analyzed-status

Для каждой сессии — есть ли уже отчёт? Есть → ✓, иначе → ·.

```bash
ls "D:\Data\Documents\Programming\Projects\WEB\VDole\.docs\dev\sessions\<alias>_*_<sid_short>.md" 2>/dev/null
```

### Шаг 5 — Таблица + выбор

Отсортируй по `mtime` DESC. Покажи:

```
Sessions for spc (newest first):

#   ✓  date        size    msgs  tools  tokens  topic
1   ·  2026-05-30  5.1 MB  289   201    98k     Email validation + OTP form
2   ✓  2026-05-30  0.8 MB  43    12     18k     i18n cleanup ru locale
3   ·  2026-05-29  2.3 MB  127   84     45k     Login redirect bug
4   ✓  2026-05-28  1.2 MB  78    34     27k     Refactor auth middleware
...

Какую сессию проанализировать? (один номер; повторный анализ перезапишет отчёт)
```

Спрашивай через `~/.claude/scripts/dialog.ps1` (AskUserQuestion не годится — список > 4).

### Шаг 6 — Pull выбранной JSONL

Сначала на сервере: `sudo cat <path> > /tmp/dev-session-<sid>.jsonl && sudo chmod 644 /tmp/dev-session-<sid>.jsonl`. Затем:

```bash
scp -P 53847 ssv@195.2.75.212:/tmp/dev-session-<sid>.jsonl C:\Users\ssv55\.claude\tmp\dev-sessions\
```

Также pull subagents/ если есть:
```bash
ssh moscow_my "sudo ls /home/<alias>/.claude/projects/<slug>/<sid>/subagents/ 2>/dev/null"
```

### Шаг 7 — Split decision

- Если `size > 5 MB` ИЛИ есть subagents → SPLIT (Шаг 7a)
- Иначе → монолитный анализ (Шаг 7b)

#### Шаг 7a — Split через подагентов

1. Разбей JSONL на куски по ~2 MB (или по 300 user/assistant пар).
2. Для каждого куска вызови `Agent` с `subagent_type: 'general-purpose'`, prompt — см. `chunk-analyze-prompt.md` в этом каталоге.
3. Каждый подагент возвращает JSON со счётчиками + примерами по 10 метрикам.
4. В main session собрать все JSON, синтезировать сводный отчёт.

Параллелить через единый Agent-вызов с несколькими `Agent` блоками в одном сообщении.

#### Шаг 7b — Монолитный

Прочитать JSONL целиком в main session, пройти все сообщения, посчитать 10 метрик, выдать отчёт.

### Шаг 8 — 10 метрик (см. METRICS.md в этом каталоге)

| # | Метрика | Как считаем |
|---|---|---|
| 1 | Test/verification rate | После tool_use Edit/Write — следующее user-сообщение содержит «тест/проверь/гонял», ИЛИ assistant сразу делает Bash(test/playwright/curl) |
| 2 | Iteration cycles | Среднее количество user-сообщений между «новой задачей» (detected by topic shift via assistant summary) и резолюцией («ок/работает/готово») |
| 3 | Tool diversity | Уникальные tool names в сессии: набор {Read, Edit, Write, Bash, Grep, Glob, Playwright, MCP_*, etc} |
| 4 | AI correction rate | user-сообщения содержащие keywords: «нет», «не так», «не туда», «стоп», «подожди», «не работает», «сначала», «перепиши», «переделай», «не надо» — посчитать долю |
| 5 | Continuity | % сессий-задач завершённых явно («готово», `/dev-09-finish`, commit) vs брошенных (последнее сообщение — вопрос/ошибка) |
| 6 | Project ownership signs | Use memory tool? Pisheт commit-messages осмысленные? Ссылается на CLAUDE.md правила? |
| 7 | Active time at keyboard | Сумма gaps между consecutive user-msgs, gap >5 мин = 5 мин (cap) |
| 8 | Work pattern | Распределение user-msgs по часам суток (timestamps) → паттерн (утренник/ночник/равномерно) |
| 9 | Pushback maturity | Из метрики 4 — какая доля содержит обоснование («потому что», «иначе», «не работает потому что», file:line ссылку) vs голое «не так» |
| 10 | Self-validation | user-сообщения которые ссылаются на проверенный факт («открыл X, там Y», «запустил, получил Z», скриншот, лог) vs повтор AI-вывода |

Каждой метрике — балл 1-10 + 1-3 конкретных example-цитаты из сессии.

### Шаг 9 — Active time расчёт

```javascript
const userTimestamps = messages
  .filter(m => m.type === 'user')
  .map(m => new Date(m.timestamp).getTime())
  .sort();

let activeMs = 0;
for (let i = 1; i < userTimestamps.length; i++) {
    const gap = userTimestamps[i] - userTimestamps[i-1];
    activeMs += Math.min(gap, 5 * 60 * 1000);  // cap at 5 min
}
// Plus 5 min credit at session start
activeMs += 5 * 60 * 1000;
```

### Шаг 10 — Запись отчёта

Шаблон `report-template.md` в этом каталоге. Заполни плейсхолдеры, запиши в:

```
D:\Data\Documents\Programming\Projects\WEB\VDole\.docs\dev\sessions\<alias>_<YYYY-MM-DD>_<sid_short>.md
```

Если файл уже есть → перезаписать (повторный анализ = новый verdict).

### Шаг 11 — Anal cost block

После записи отчёта — посчитать сколько потратил **сам анализатор** (твоя текущая session + все subagent JSONL'ы):

```bash
# Most recent session JSONL for this VDole project
SESSION_JSONL=$(ls -t ~/.claude/projects/d--Data-Documents-Programming-Projects-WEB-VDole/*.jsonl | head -1)
SUBAGENTS_DIR="${SESSION_JSONL%.jsonl}/subagents"

# Aggregate tokens via bun (script from global CLAUDE.md "Claude Code Session Storage")
bun -e "
const fs=require('fs');
function agg(f){let inp=0,cc=0,cr=0,out=0,n=0;
  for(const l of fs.readFileSync(f,'utf-8').split('\n').filter(Boolean)){
    try{const o=JSON.parse(l);if(o.message?.usage){const u=o.message.usage;
      inp+=u.input_tokens||0;cc+=u.cache_creation_input_tokens||0;
      cr+=u.cache_read_input_tokens||0;out+=u.output_tokens||0;n++}}catch{}}
  return {messages:n,input:inp,cache_create:cc,cache_read:cr,output:out};}
const main=agg(process.argv[1]);
const subDir=process.argv[2];
let subs=[];
try{subs=fs.readdirSync(subDir).filter(f=>f.endsWith('.jsonl')).map(f=>agg(subDir+'/'+f));}catch{}
const total={messages:main.messages+subs.reduce((s,x)=>s+x.messages,0),
  input:main.input+subs.reduce((s,x)=>s+x.input,0),
  cache_create:main.cache_create+subs.reduce((s,x)=>s+x.cache_create,0),
  cache_read:main.cache_read+subs.reduce((s,x)=>s+x.cache_read,0),
  output:main.output+subs.reduce((s,x)=>s+x.output,0),
  subagent_count:subs.length};
console.log(JSON.stringify({main,subs_aggregate:subs.length?{messages:subs.reduce((s,x)=>s+x.messages,0),input:subs.reduce((s,x)=>s+x.input,0)}:null,total},null,2));
" "$SESSION_JSONL" "$SUBAGENTS_DIR"
```

Дельта стартового timestamp до текущего = wall-clock. Дописать в КОНЕЦ отчёта секцию `## Analyzer cost` (см. report-template.md).

### Шаг 12 — Финальный вывод

```
✓ Анализ сессии <sid_short> завершён.
Отчёт: D:\Data\Documents\Programming\Projects\WEB\VDole\.docs\dev\sessions\<alias>_<date>_<sid_short>.md

Краткий verdict: <одна фраза из отчёта — общая оценка / процент engagement>

Анализ стоил: ~<N>k токенов, <M> минут wall-clock.
```

## Полная справка по метрикам

См. `METRICS.md` в этом каталоге — что каждая из 10 метрик измеряет, как считается, на что смотреть. Открыть: `cat C:\Users\ssv55\.claude\skills\dev-sessions-analyze\METRICS.md`.

## Что НЕ делать

- Не анализировать сессию которая **сейчас активна** (mtime < 5 мин назад — дев ещё работает, контекст может сломаться). Warning + предложить подождать.
- Не показывать в отчёте содержимое `.credentials.json`, `.env.development`, или приватные ключи если они мелькнули в сессии (sanitize: маска `***REDACTED***`).
- Не выводить полный текст сессии в чат — только агрегаты и цитаты-примеры (3-10 слов).
- Не комментировать **личное** — рабочие часы, паттерн «ночник» — это **информация**, не повод для критики. Рекомендации только по профессиональной части.
