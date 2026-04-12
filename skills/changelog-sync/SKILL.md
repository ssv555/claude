---
name: changelog-sync
description: Sync archive sessions and orphan commits into changelog drafts (reads sessions, generates 3-level texts, inserts into SQLite)
disable-model-invocation: false
---

Generate changelog entries from archive sessions and orphan git commits.
This is the **primary data entry tool** for the changelog. Claude reads session files, generates business-friendly 3-level Russian texts, and inserts drafts into SQLite.

Storage: `back/data/changelog.sqlite` — file-based, deploys as a regular file. If lost — just rerun this skill.

**CRITICAL: Process items sequentially. Output progress to chat after each item. No subagents.**

## Step 0: Check DB Connection

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog-sqlite';
const ok = changelogDb.checkConnection();
console.log(ok ? 'DB OK' : 'DB FAIL');
if (!ok) process.exit(1);
process.exit(0);
"
```

If this fails → **STOP immediately**. Report the error to the user.

## Step 1: Read Sync State

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog-sqlite';
const state = changelogDb.getSyncState();
console.log(JSON.stringify(state ?? { last_sync_at: null, sync_count: 0 }));
process.exit(0);
"
```

- If `last_sync_at` is `null` → first run, process ALL sessions and commits
- Otherwise → process only items with date AFTER `last_sync_at` (second precision)

## Step 2: Scan New Archive Sessions

```bash
ls -1 docs/archive/sessions/*.md 2>/dev/null | sort
```

Get already-processed session files:

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog-sqlite';
const files = changelogDb.getProcessedSessionFiles();
for (const f of files) console.log(f);
process.exit(0);
"
```

Filter: keep only files that:
1. Are NOT in the processed set
2. Have filename date > `last_sync_at` (or all if first run)
3. Match valid filename format: `YYYY.MM.DD_HH.MM_developer_Topic.md`

Sort chronologically. This is the **session queue**.

## Step 3: Scan Orphan Commits

Calculate the scan floor: `last_sync_at - 30 days` (buffer for manually deleted entries). If `last_sync_at` is null → scan all commits.

```bash
# Calculate floor date (30 days before last_sync_at, or "1 year ago" for first run)
bun -e "
const lastSync = '<last_sync_at_or_null>';
if (lastSync === 'null') {
  const d = new Date(); d.setFullYear(d.getFullYear() - 1);
  console.log(d.toISOString().slice(0, 10));
} else {
  const d = new Date(lastSync); d.setDate(d.getDate() - 30);
  console.log(d.toISOString().slice(0, 10));
}
process.exit(0);
"
```

```bash
git log --after="<floor_date>" --format="%H|%ai|%an|%s" --no-merges
```

Get already-processed commit hashes:

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog-sqlite';
const hashes = changelogDb.getProcessedCommitHashes();
for (const h of hashes) console.log(h);
process.exit(0);
"
```

For each commit NOT in the processed set:
- Check if it overlaps with any session by date ± 2 hours and same developer
- If it overlaps → skip (covered by session)
- If it doesn't overlap AND has >3 files changed → it's an orphan
- Check files changed: `git diff --stat <hash>^..<hash> | tail -1`

**Collect orphans into a SEPARATE list. Do NOT add them to the session queue.**

> **Note**: `getProcessedCommitHashes()` is the authoritative deduplication gate. The date floor is only an optimization to avoid scanning ancient history — always trust the hash set over the date.

## Step 4: Process Sessions

For each session in the queue:

### 4a. Output Progress
Print to chat: `[N/total] filename — парсинг...`

### 4b. Read Content
Read the file with Read tool, parse metadata from filename and content.

### 4c. Generate 3-Level Texts (Russian only)

Based on the content, generate:

**Level 1 — title** (max 100 chars): Short business headline for executives.
- NO technical terms (no "middleware", "schema", "refactoring")
- Examples: "Авторизация через VK", "Главная страница инвесторов", "Система безопасности аккаунтов"

**Level 2 — summary** (2-4 sentences): For project managers and developers.
- What changed and why. No code snippets.
- Example: "Добавлена авторизация через VK OAuth. Пользователи могут входить через VK аккаунт с автоматической привязкой к профилю. Реализована синхронизация аватара и имени из VK."

**Level 3 — details** (structured paragraph): Technical details for developers.
- Modules created/modified, libraries used, algorithms, storage
- NO raw code, but technical enough to understand scope
- Example: "Создан OAuth flow для VK: callback endpoint в authVk.ts, обмен code→token через VK API v5.199. Данные пользователя сохраняются в settings.auth_app.vk (JSONB). Добавлен generated column vk_user_id для быстрого поиска. Библиотека: встроенный fetch."

**Category**: One of: `feature`, `bugfix`, `security`, `infrastructure`, `ui_ux`, `devops`, `docs`, `refactoring`, `performance`

**Tags**: 1-5 keywords (e.g., `["auth", "vk", "oauth"]`)

### 4d. Insert Draft into SQLite

Use the data access module:

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog-sqlite';
const id = changelogDb.create({
  title: '<TITLE>',
  summary: '<SUMMARY>',
  details: '<DETAILS>',
  category: '<CATEGORY>',
  tags: <TAGS_JSON>,
  developer: '<DEVELOPER>',
  durationMin: <DURATION_OR_NULL>,
  entryDate: '<YYYY-MM-DD HH:MM>',
  sessionFile: '<SESSION_FILE_OR_NULL>',
  commitHash: '<COMMIT_HASH_OR_NULL>',
});
console.log('OK:' + id);
process.exit(0);
"
```

**IMPORTANT**: Escape all single quotes in text values with `'\''` for bash. Or use double quotes with escaped inner doubles.

### 4e. Output Completion
Print: `[N/total] готово, черновик создан`

## Step 5: Handle Orphan Commits (interactive)

If no orphans found → skip to Step 6.

### 5a. Present Orphan List

Print a numbered table to chat:

```
Найдены сиротские коммиты (не покрыты сессиями):

 #  | Дата       | Автор | Файлов | Сообщение
----|------------|-------|--------|----------
 1. | 2026-04-11 | ssv   | 17     | update changelog, service ui, auth fixes
 2. | ...        | ...   | ...    | ...
```

### 5b. Ask User

Use `AskUserQuestion` to ask:

> Что сделать с сиротскими коммитами?
> - Номера через запятую (например `1,3`) — создать сессию + черновик для выбранных
> - `все` — создать для всех
> - `нет` — пропустить все

### 5c. Process Approved Orphans

For each approved orphan commit:

1. **Gather commit data**: `git show --stat <hash>` and `git log -1 --format="%B" <hash>`

2. **Generate session file** in `docs/archive/sessions/` with name derived from commit:
   - Filename: `YYYY.MM.DD_HH.MM_<developer>_<Topic_from_commit_msg>.md`
   - Developer mapping: `ssv555`/`ssv` → `ssv`, `Kirill`/`WhiteDullahan` → `kirill`
   - Topic: first 2-3 meaningful words from commit message, CamelCase, underscores between words

   Session file content:
   ```markdown
   # PROMT

   > Автогенерация из сиротского коммита <short_hash>

   **Model**: orphan commit | **Branch**: main | **Начало**: <commit_date> | **Конец**: <commit_date> | **Длительность**: unknown

   ## Выполнено

   <parsed from commit message and diff stats — list what was done>

   ### Модифицированные файлы

   <file list from git show --stat>

   ---

   ## TODO

   - Нет
   ```

3. **Generate 3-level texts** (same rules as Step 4c)

4. **Insert changelog draft** with both `sessionFile` (the generated file) and `commitHash`

5. **Output**: `[orphan N/M] <hash_short> — сессия создана, черновик добавлен`

## Step 6: Update Sync State

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog-sqlite';
changelogDb.updateSyncState({
  lastSyncAt: new Date().toISOString(),
  lastSessionFile: '<LAST_SESSION_FILE>',
  lastCommitHash: '<LAST_COMMIT_HASH>',
});
console.log('Sync state updated');
process.exit(0);
"
```

## Step 7: Final Report

Print summary to chat:

```
Changelog sync завершён:
- Сессий обработано: N
- Сиротских коммитов найдено: X
- Сиротских коммитов обработано: Y (сессии созданы)
- Сиротских коммитов пропущено: Z
- Черновиков создано: N+Y
- Ревью: /service/changelog (включить "Показать черновики")
```

## Rules

- **Sequential processing** — one item at a time, progress visible in chat
- **No subagents** — everything in current session
- **No external AI APIs** — Claude generates texts directly
- **Russian only** — all generated content in Russian (service section is for Russian devs/owners)
- **Idempotent** — unique constraints on session_file and commit_hash prevent duplicates
- **Self-healing** — if changelog.sqlite is missing, the module auto-creates it with tables
- **Escape bash** — all text values must be properly escaped before insertion
- **Duration**: Parse from session metadata `Xh Ym` → minutes. If no metadata → null
- **entryDate**: Parse from session filename `YYYY.MM.DD_HH.MM` → `YYYY-MM-DD HH:MM` format
- **Orphan sessions**: Generated session files are real archive files — they will be found by future syncs, so `sessionFile` must be set to prevent re-processing
