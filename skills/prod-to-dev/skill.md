---
name: prod-to-dev
description: Backup production DB (moscow) and restore to local dev
disable-model-invocation: false
allowed-tools: mcp__moscow__execute-command, mcp__moscow__download, Bash(powershell*), Read, Glob
model: sonnet
context: fork
---

Backup production database via SSH MCP (moscow) and restore to local dev PostgreSQL.

**CRITICAL: Execute steps strictly in order. Do NOT run steps in parallel.**

## Step 1 — Backup on production

Run via `mcp__moscow__execute-command`:
```
cd /var/www/server_bun/scripts/deploy && bash 01-backup-db.sh
```
Parse output to extract backup filename and path (e.g. `/var/backups/serverbun/backup_YYYY-MM-DD_HH-MM-SS.dump`).

## Step 2 — Download dump to local .tmp/

Use `mcp__moscow__download`:
- remotePath: the full backup path from Step 1
- localPath: `{cwd}/.tmp/{filename}` (use `pwd` to get cwd)

## Step 3 — Get local DATABASE_URL

Read `.env.development` from project root. Extract `DATABASE_URL` value.
Replace `0.0.0.0` with `localhost` in the URL if present.

## Step 4 — Find local pg_restore

Find PostgreSQL installation:
```powershell
powershell.exe -Command "Get-ChildItem 'C:\Program Files\PostgreSQL' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty Name"
```
Construct path: `C:\Program Files\PostgreSQL\{version}\bin\pg_restore.exe`

## Step 5 — Restore to local dev DB

Run via PowerShell (use connection string directly, NOT $env:PGPASSWORD):
```powershell
powershell.exe -Command "& 'C:\Program Files\PostgreSQL\{version}\bin\pg_restore.exe' -d '{DATABASE_URL}' --clean --if-exists '{dump_path}' 2>&1"
```

If exit code 0 or no output — success.

## Step 6 — Verify and report

Run via PowerShell using `psql.exe` from same PostgreSQL directory:
```powershell
powershell.exe -Command "& 'C:\Program Files\PostgreSQL\{version}\bin\psql.exe' -d '{DATABASE_URL}' -c 'SELECT (SELECT count(*) FROM users) as users, (SELECT count(*) FROM expenses) as expenses, (SELECT count(*) FROM expenses_categories) as categories, (SELECT count(*) FROM expenses_periodicals) as periodicals, (SELECT count(*) FROM donation_pays) as donations;' 2>&1"
```

Output final report in this format:

```
Продовая БД восстановлена в локальный dev:

| Таблица | Записей |
|---------|---------|
| users | {n} |
| expenses | {n} |
| expenses_categories | {n} |
| expenses_periodicals | {n} |
| donation_pays | {n} |

Дамп: .tmp/{filename}
```

## Rules

- NEVER use `$env:PGPASSWORD` — PowerShell escaping breaks in Bash tool
- ALWAYS use connection string directly in `-d` parameter
- NEVER hardcode PostgreSQL version — detect dynamically
- NEVER hardcode DATABASE_URL — read from `.env.development`
- Dump files go to `.tmp/` directory only
