---
name: prod-to-dev
description: Backup production DB and restore to local dev. Project-aware via tests/skills/prod-to-dev.md (servers, MCP names, paths, target tables). Server prefix = pro|tst|ru (default pro). If prefix omitted → AskUserQuestion.
disable-model-invocation: false
allowed-tools: Bash(powershell*), Read, Glob, Grep
model: sonnet
context: fork
---

Backup production database via SSH MCP and restore to local dev PostgreSQL.

**CRITICAL: Execute steps strictly in order. Do NOT run steps in parallel.**

## Step 0 — Resolve project config and prefix

1. Read project-config from `<cwd>/tests/skills/prod-to-dev.md` (project root). Required fields:
   - **servers**: map `pfx → { mcp_server, backup_script, dump_dir }`
   - **target_env_file**: `.env.development` or similar (file in project root with local DATABASE_URL)
   - **tables_count**: list of tables to count after restore (for the report)
   - **dump_local_dir**: where to drop the downloaded dump (default `.tmp/`)

   If the file is missing — STOP and ask user: «Не нашёл `tests/skills/prod-to-dev.md` — нужен project-конфиг с server-картой. Создать?»

2. Resolve server prefix:
   - If user passed an arg (`/prod-to-dev tst`) — use it.
   - Else — `AskUserQuestion`:
     - **Question**: «Откуда backup-ить prod DB?»
     - **Options** in fixed order, `pro` first:
       - `pro — основной прод`
       - `tst — фолбэк`
       - `ru — будущий боевой (если настроен)`
   - Verify the chosen prefix exists in `servers` map. If not — report «Префикс `<pfx>` не настроен в tests/skills/prod-to-dev.md» and stop.

3. Cache the resolved server config: `MCP=<mcp_server>`, `BACKUP_SCRIPT=<backup_script>`.

## Step 1 — Backup on production

Run via the configured MCP `mcp__<MCP>__execute-command`:

```
bash <BACKUP_SCRIPT>
```

Parse output to extract backup filename and full path on the server (typically printed by the backup script).

## Step 2 — Download dump to local dump_local_dir

Use `mcp__<MCP>__download`:
- `remotePath`: full backup path from Step 1
- `localPath`: `{cwd}/<dump_local_dir>/{filename}` (use `pwd` to get cwd)

## Step 3 — Get local DATABASE_URL

Read `<target_env_file>` (path from project-config) from project root. Extract `DATABASE_URL` value.
Replace `0.0.0.0` with `localhost` in the URL if present.

## Step 4 — Find local pg_restore

Find PostgreSQL installation:
```powershell
powershell.exe -Command "Get-ChildItem 'C:\Program Files\PostgreSQL' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name"
```
Construct path: `C:\Program Files\PostgreSQL\{version}\bin\pg_restore.exe`

## Step 5 — Restore to local dev DB

Run via PowerShell (use connection string directly, NOT `$env:PGPASSWORD`):
```powershell
powershell.exe -Command "& 'C:\Program Files\PostgreSQL\{version}\bin\pg_restore.exe' -d '{DATABASE_URL}' --clean --if-exists '{dump_path}' 2>&1"
```

Exit 0 / no output → success.

## Step 6 — Verify and report

Build a count-query from `tables_count` (project-config). Example for `[users, expenses, businesses]`:

```sql
SELECT (SELECT count(*) FROM users) AS users,
       (SELECT count(*) FROM expenses) AS expenses,
       (SELECT count(*) FROM businesses) AS businesses;
```

Run via PowerShell + `psql.exe`:
```powershell
powershell.exe -Command "& 'C:\Program Files\PostgreSQL\{version}\bin\psql.exe' -d '{DATABASE_URL}' -c '<query>' 2>&1"
```

Final report:

```
Продовая БД (<pfx>, <url-from-config>) восстановлена в локальный dev:

| Таблица | Записей |
|---------|---------|
| <table_1> | {n} |
| <table_2> | {n} |
| ...     | ... |

Дамп: <dump_local_dir>/{filename}
```

## Rules

- NEVER use `$env:PGPASSWORD` — PowerShell escaping breaks in Bash tool
- ALWAYS use connection string directly in `-d` parameter
- NEVER hardcode PostgreSQL version — detect dynamically
- NEVER hardcode DATABASE_URL — read from `<target_env_file>` declared in project-config
- NEVER hardcode server / MCP / paths / tables — read from `tests/skills/prod-to-dev.md`
- Dump files go to `<dump_local_dir>` only (default `.tmp/`)
