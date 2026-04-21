---
name: changelog-sync
description: Sync archive sessions and orphan commits into changelog drafts (reads sessions, generates 3-level texts, inserts into Postgres)
model: sonnet
effort: max
disable-model-invocation: false
---

Generate changelog entries from archive sessions and orphan git commits.
This is the **primary data entry tool** for the changelog. Claude reads session files, generates business-friendly 3-level Russian texts, and inserts drafts into Postgres.

Storage: Postgres tables `changelog_entries` and `changelog_sync_state` (same DB as the rest of the app). If rows are lost — just rerun this skill; it's idempotent via UNIQUE(`session_file`) and UNIQUE(`commit_hash`) + `ON CONFLICT DO NOTHING`.

**CRITICAL: Process items sequentially for text generation (one per item, visible progress in chat). Database writes are batched via `createMany` (one `INSERT ... VALUES (...),(...) ON CONFLICT DO NOTHING` per ~50 rows) — ArrayDML-style, single round-trip per batch. No subagents.**

## Step 0: Check DB Connection

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog';
const ok = await changelogDb.checkConnection();
console.log(ok ? 'DB OK' : 'DB FAIL');
if (!ok) process.exit(1);
process.exit(0);
"
```

If this fails → **STOP immediately**. Report the error to the user (Postgres down, schema missing, etc.). Do not try to create tables manually — run `bun run db:push` instead.

**Record start time immediately after DB check:**
```js
const SYNC_START_TIME = new Date().toISOString(); // used in Step 6
```
Save this value in memory — it will be written as `lastSyncAt` in Step 6, not the end time. This ensures sessions created DURING this skill run are picked up in the next sync.

## Step 1: Read Sync State

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog';
const state = await changelogDb.getSyncState();
console.log(JSON.stringify(state ?? { last_sync_at: null, sync_count: 0 }));
process.exit(0);
"
```

- If `last_sync_at` is `null` → first run, process ALL sessions and commits.
- Otherwise → process only items with date AFTER `last_sync_at` (second precision).

Dedup is enforced at DB level (UNIQUE + ON CONFLICT DO NOTHING), so re-processing is safe — it just drops duplicate rows silently.

## Step 2: Scan New Archive Sessions

```bash
ls -1 docs/archive/sessions/*.md 2>/dev/null | sort
```

Get already-processed session files:

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog';
const files = await changelogDb.getProcessedSessionFiles();
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
import * as changelogDb from './back/src/db/changelog';
const hashes = await changelogDb.getProcessedCommitHashes();
for (const h of hashes) console.log(h);
process.exit(0);
"
```

For each commit NOT in the processed set:

1. **Get file list**: `git diff --name-only <hash>^..<hash>`
2. **Apply blacklist** — drop files matching:
   - `docs/ktu/**` (КТУ — internal contribution metrics, not for changelog)
   - `.docs/**` (private knowledge base / ChatGPT archives)

   If 0 files remain after filtering → **skip the commit entirely** (nothing to record).
3. **Find overlapping session** by date ±2h and same developer. If found:
   - Read the session MD file with Read tool
   - Parse the `### Модифицированные файлы` section into a set of file paths
   - **If the section is missing** (legacy session, mostly pre-2026-03-22) → fallback: trust the session, skip the commit (covered). Print a warning: `[warn] Session <file> has no '### Модифицированные файлы' section — commit <hash_short> assumed covered. Verify manually.`
   - **If the section is present** and any of the commit's (post-blacklist) files is NOT in the session's file set → commit is **not fully covered** → treat as orphan
   - Else (every commit file is listed in the session) → skip (covered)
4. **No overlap** → orphan

**All orphans are auto-inserted as drafts in Step 5. No interactive prompts. No file-count filter.**

> **Note**: `getProcessedCommitHashes()` is the authoritative deduplication gate. The date floor is only an optimization to avoid scanning ancient history — always trust the hash set over the date.

## Step 4: Process Sessions

**Strategy: generate texts sequentially (visible progress), push drafts into a batch array, flush to DB every 50 rows via `createMany`.**

Declare the batch at the start of the step:
```js
const sessionBatch = []   // CreateChangelogEntry[]
const BATCH_SIZE = 50
```

For each session in the queue:

### 4a. Output Progress
Print to chat: `[N/total] filename — парсинг...`

### 4b. Read Content
Read the file with Read tool, parse metadata from filename and content.

### 4b2. Compute Active Duration (gap-based, with dedup)

**Three sub-rules, applied in order. This is the ONLY place duration is set — do not second-guess it later.**

**Rule A — Continuation archives get zero duration.**
Detect either signal:
- Filename ends with `_N.md` where N ≥ 0 (e.g. `..._0.md`, `..._2.md`, `..._3.md`)
- Content contains `"Повторный вызов /session-archive"` or `"Continuation archive"`

→ Set `durationMin = 0`, `durationRawMin = 0`. Skip to 4c. Reason: these .md files share a JSONL with their parent archive. The parent already owns the full duration.

**Rule B — Use .md-range slicing when multiple .md share one JSONL.**
For non-continuation files:

```bash
bun -e "
import { findJsonlForSession, parseSessionMdRange, computeActiveDurationInRange, computeActiveDuration } from './back/src/lib/session-duration';
const jsonl = await findJsonlForSession('<SESSION_FILENAME>');
if (!jsonl) { console.log('NO_JSONL'); process.exit(0); }
const range = await parseSessionMdRange('docs/archive/sessions/<SESSION_FILENAME>');
const r = range
  ? await computeActiveDurationInRange(jsonl, range.startMs, range.endMs, 60)
  : await computeActiveDuration(jsonl, 60);
console.log(JSON.stringify({ ...r, jsonl, ranged: !!range }));
process.exit(0);
"
```

The range slice guarantees two `.md` files sharing a JSONL each claim only their segment of the timeline — no double-counting.

**Rule C — No-JSONL fallback with sanity cap.**
If `NO_JSONL`:
- Parse `Длительность` from the .md (raw minutes)
- If `rawMin ≤ 240` → use it as both `durationMin` and `durationRawMin`. Print: `[warn] JSONL not found for <file> — using raw .md value (<rawMin>m)`.
- If `rawMin > 240` → set `durationMin = null`, `durationRawMin = rawMin`. Print: `[warn] JSONL not found for <file> AND raw=<rawMin>m exceeds 240m cap — activeMin=null (manual review required)`.

Reason: without JSONL we cannot segment idle gaps; a 27h overnight session silently inflates totals by 10×. Null is honest.

**Rule D — JSONL dedup (cross-file).**
Maintain a `seenJsonls = new Set<string>()` across the whole Step 4 loop. If the current file's JSONL path is already in the set AND no range was applied (Rule B failed):

→ Set `durationMin = 0`, `durationRawMin = 0`. Print: `[warn] <file> shares JSONL with an earlier session and has no parseable range — durationMin=0 (already counted)`.

Otherwise add the JSONL path to `seenJsonls` and use the computed values.

Gap threshold: fixed 60 min. Do not ask the user.

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

**Category**: One of: `feature`, `bugfix`, `security`, `infrastructure`, `ui_ux`, `devops`, `docs`, `refactoring`, `performance`, `technical`

- `technical` — auto-generated entries from orphan commits and uncovered overlap commits.

**Tags**: 1-5 keywords (e.g., `["auth", "vk", "oauth"]`)

### 4d. Push Draft into Batch

Append to `sessionBatch` (array in memory — no DB call yet):

```js
sessionBatch.push({
  title: '<TITLE>',
  summary: '<SUMMARY>',
  details: '<DETAILS>',
  category: '<CATEGORY>',
  tags: <TAGS_ARRAY>,
  developer: '<DEVELOPER>',
  durationMin: <ACTIVE_DURATION_OR_NULL>,
  durationRawMin: <RAW_DURATION_OR_NULL>,
  entryDate: '<YYYY-MM-DD HH:MM>',
  sessionFile: '<SESSION_FILE_OR_NULL>',
  commitHash: '<COMMIT_HASH_OR_NULL>',
  isPublished: false,
})
```

### 4e. Flush Batch When Full

**Pre-insert sanity pass (mandatory, on every batch before createMany):**

Walk the batch once, assert the invariants, auto-correct obvious violations, abort with `console.error` + `process.exit(1)` on anything unfixable:

1. **No two rows with `durationMin > 0` sharing the same `YYYY.MM.DD_HH.MM_<dev>` prefix.** If found and Rules A–D failed to catch them → zero the duration of all but the longest-content row. Print: `[sanity] duplicate-prefix dup at <prefix> — kept <file>, zeroed <others>`.
2. **No row with `durationMin > 600`.** Active session > 10h is physically impossible — means a bug slipped past Rule C. Cap at 600 and print: `[sanity] capped <file> from <X>m to 600m`.
3. **`durationMin ≤ durationRawMin` (when both non-null).** If violated, swap them and print warning.
4. **`entryDate` matches filename prefix.** If not, print warning (data will still insert — just flag).

These checks are safety net, not primary logic — they should almost never fire if 4b2 did its job.

When `sessionBatch.length >= BATCH_SIZE` — flush:

```bash
# Serialize the array via a temp JSON file so we don't fight bash escaping.
# (Or pass inline for small batches — either works.)
bun -e "
import * as changelogDb from './back/src/db/changelog';
import { readFileSync, unlinkSync } from 'node:fs';
const entries = JSON.parse(readFileSync('/tmp/cl-batch.json', 'utf8'));
const r = await changelogDb.createMany(entries);
console.log(JSON.stringify(r));
unlinkSync('/tmp/cl-batch.json');
process.exit(0);
"
```

Output: `[batch] inserted=N skipped=M (total N/total sessions)`.

### 4f. Output Completion
Print: `[N/total] готово, в батче`

## Step 5: Handle Orphan Commits (auto)

If no orphans found → skip to Step 5.5.

**No interactive prompts. Every orphan is auto-processed into a `technical` changelog draft + a generated session file. User reviews drafts later via `/service/changelog` → "Показать черновики".**

### 5a. Print Orphan List (informational only)

```
Сиротские коммиты для авто-обработки (категория technical):

 #  | Дата       | Автор | Файлов* | Сообщение
----|------------|-------|---------|----------
 1. | 2026-04-11 | ssv   | 17      | update changelog, service ui, auth fixes
 2. | ...        | ...   | ...     | ...

* — после blacklist (docs/ktu/**, .docs/**)
```

### 5b. Process Every Orphan

For each orphan commit (no user confirmation):

1. **Gather commit data**: `git show --stat <hash>` and `git log -1 --format="%B" <hash>`

2. **Generate session file** in `docs/archive/sessions/`:
   - Filename: `YYYY.MM.DD_HH.MM_<developer>_<Topic_from_commit_msg>.md`
   - Developer mapping: `ssv555`/`ssv` → `ssv`, `Kirill`/`WhiteDullahan` → `kirill`
   - Topic: first 2-3 meaningful words from commit message, CamelCase

   Session file content:
   ```markdown
   # PROMT

   > Автогенерация из сиротского коммита <short_hash>

   **Model**: orphan commit | **Branch**: main | **Начало**: <commit_date> | **Конец**: <commit_date> | **Длительность**: unknown

   ## Выполнено

   <parsed from commit message and diff stats>

   ### Модифицированные файлы

   <file list from git show --stat, excluding blacklisted paths>

   ---

   ## TODO

   - Нет
   ```

3. **Generate 3-level texts** (same rules as Step 4c). **Category MUST be `technical`**. Texts describe ONLY the post-blacklist files.

4. **Push to the same batch array** (or a separate `orphanBatch` — both use `createMany`) with `sessionFile` set to the generated file and `commitHash` set to the orphan hash. Category = `technical`.

5. **Output**: `[orphan N/M] <hash_short> — technical в батче`

### 5c. Final Flush

After both Step 4 and Step 5 are done, flush any remaining rows:

```js
if (sessionBatch.length > 0) {
  const r = await changelogDb.createMany(sessionBatch)
  console.log(`[final batch] inserted=${r.inserted} skipped=${r.skipped}`)
  sessionBatch.length = 0
}
```

## Step 5.5: Import Orphan JSONL Sessions

Claude Code keeps every session's JSONL in `~/.claude/projects/<slug>/`, even when the user never ran `/session-archive` for it. Those are "orphan JSONLs": real work time with no corresponding .md in `docs/archive/sessions/`.

Run the importer:

```bash
bun run back/src/scripts/orphan_jsonl_import.ts
```

What it does:
- For every JSONL without a pair in `docs/archive/sessions/`:
  - Skips if gap-based `activeMin < 30` (filters out noise).
  - Skips hook-spawned child Claude sessions by matching the canonical system prompt prefix.
  - Generates a synthetic `YYYY.MM.DD_HH.MM_<dev>_Orphan_<Topic>_<hash>.md` with a stripped IDE-envelope user prompt and edited-file list.
  - Classifies a changelog category heuristically (prompt keywords + file paths).
  - Inserts drafts via `createMany` (batched) with `durationMin = activeMin`, `durationRawMin = rawMin`, `tags = ['orphan', <category>]`.

Rerun is safe — both the filename-based pre-filter and the DB-level `ON CONFLICT DO NOTHING` drop duplicates.

## Step 6: Update Sync State

```bash
bun -e "
import * as changelogDb from './back/src/db/changelog';
await changelogDb.updateSyncState({
  lastSyncAt: '<SYNC_START_TIME>',
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
- Коммитов в blacklist (пропущено целиком): K
- Сиротских коммитов авто-обработано: Y (technical, сессии созданы)
- Черновиков вставлено: N+Y
- Пропущено по dedup (ON CONFLICT): Z
- Ревью: /service/changelog (включить "Показать черновики")
```

## Rules

- **Sync state write is LAST, nowhere else** — `updateSyncState` runs ONLY in Step 6, after all data insertion completes. Writing earlier (even on user complaint) breaks fault tolerance: if the skill then crashes, newly-queued sessions created during the run get silently skipped next time. The `SYNC_START_TIME` variable is captured in Step 0 and sits in memory until Step 6.
- **Sequential text generation** — one session at a time, progress visible in chat. Claude generates texts per-session; this is the real bottleneck.
- **Batched DB writes** — `createMany` every 50 rows + final flush. ArrayDML-style: single `INSERT ... VALUES (...), (...) ... ON CONFLICT DO NOTHING` per batch.
- **No subagents** — everything in current session.
- **No external AI APIs** — Claude generates texts directly.
- **Russian only** — all generated content in Russian.
- **Idempotent** — UNIQUE on `session_file` and `commit_hash` + `ON CONFLICT DO NOTHING`; re-runs drop duplicates silently.
- **Self-healing schema** — if tables are missing, run `bun run db:push`. Do NOT create tables manually in the skill.
- **Duration**: Parse from session metadata `Xh Ym` → minutes. If no metadata → null.
- **entryDate**: Parse from session filename `YYYY.MM.DD_HH.MM` → `YYYY-MM-DD HH:MM` format.
- **Orphan sessions**: Generated session files are real archive files — they will be found by future syncs, so `sessionFile` must be set to prevent re-processing.
- **Gap-based duration**: `durationMin` stored in PG is ALWAYS the active figure (idle gaps > 60 min removed). `durationRawMin` keeps the original end-minus-start. The .md file itself is NEVER modified — Postgres is authoritative.
