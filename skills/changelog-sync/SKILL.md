---
name: changelog-sync
description: Sync archive sessions and orphan commits into changelog drafts (reads sessions, generates 3-level texts, inserts into SQLite)
disable-model-invocation: false
allowed-tools: Bash(bun *),Bash(git *),Bash(ls *),Bash(wc *),Read,Glob,Grep
model: opus
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

Sort chronologically. This is the work queue.

## Step 3: Scan Orphan Commits (after sessions)

```bash
git log --after="<last_sync_at or earliest date>" --format="%H|%ai|%an|%s" --no-merges
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
- If it doesn't overlap AND has >3 files changed → it's an orphan, add to queue
- Check files changed: `git diff --stat <hash>^..<hash> | tail -1`

## Step 4: Process Queue Sequentially

For each item in the queue (sessions first, then orphan commits):

### 4a. Output Progress
Print to chat: `[N/total] filename — парсинг...`

### 4b. Read Content
- **Session**: Read the file with Read tool, parse metadata from filename and content
- **Orphan commit**: Run `git show --stat <hash>` and `git log -1 --format="%B" <hash>`

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

## Step 5: Update Sync State

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

## Step 6: Final Report

Print summary to chat:

```
Changelog sync завершён:
- Сессий обработано: N
- Сиротских коммитов: M
- Черновиков создано: N+M
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
