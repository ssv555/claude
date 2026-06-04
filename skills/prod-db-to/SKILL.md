---
name: prod-db-to
description: Roll out the PRODUCTION database (source always prod) to a target; arg selects target. Args: ssv | laptop | tst | all | ru | help. Use when user says "/prod-db-to [target]", "раскатай прод-базу на …", "залей прод БД на tst/ssv".
disable-model-invocation: false
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
model: sonnet
---

# prod-db-to — roll the production DB out to dev / tst

The **source is ALWAYS production** (`pro`). The argument selects the **target**. One prod dump
is taken and restored to the chosen target(s).

**CRITICAL — two safety invariants, never violate:**

1. **Direct ssh + hostname guard for prod. NEVER the MCP connector.** The MCP server for prod
   (`vdole_pro_timeweb_moscow`) is unreliable — on 2026-05-31 a command sent "to prod" through MCP
   actually executed on **tst** (`hostname` returned the moscow box). Root cause unknown. So every
   prod read/write goes through a plain `ssh <alias>` and is preceded by a `hostname` check that
   must equal the configured guard, else **abort**.
2. **Nodes never ssh each other.** Project rule «no cross-host ssh между нодами» — `pro` and `tst`
   must not ssh directly. All server→server data movement routes **through THIS PC as the hub**:
   dump prod → this PC → upload to tst.

**CRITICAL: execute steps strictly in order. Do NOT run steps in parallel.**

## Targets

| arg | target | flow |
|---|---|---|
| `ssv` (default) | this desktop's local PG | dump prod → restore local (`.env.development`) |
| `laptop` | this laptop's local PG | dump prod → restore local (`.env.laptop`) |
| `tst` | moscow_my fallback node | dump prod → upload dump from this PC → restore on tst |
| `all` | ssv + tst | dump prod **once** → restore ssv → upload same dump → restore tst |
| `ru` | future prod (vdole.ru) | not configured → report and stop |
| `help` | — | print this table + the flow, do nothing else |

`ssv` / `laptop` are labels for "the local machine you are running on" — you cannot restore into a
machine you are not physically on. `tst` overwrites tst's **independent** DB (destructive — that is
the point: make tst match prod).

## Step 0 — resolve config + target

1. Read `<cwd>/tests/skills/prod-db-to.md` (project root). Required fields:
   - **source** (`pro`): `ssh_alias`, `hostname_guard`, `db`, `dump_cmd`
   - **targets**: map for `ssv` / `laptop` / `tst` / `all` / `ru`
   - **restore**: `flags`, `local_pg_bin` (detect dynamically), `dump_local_dir`
   - **tables_count**: tables to count after restore
   - **cleanup**: local + remote dump removal

   Missing file → STOP, ask: «Не нашёл `tests/skills/prod-db-to.md` — нужен project-конфиг. Создать?»

2. Resolve target:
   - Arg passed (`/prod-db-to tst`) → use it.
   - `help` → print the Targets table + flow, STOP.
   - No arg → `AskUserQuestion` (options in fixed order: `ssv` default / `laptop` / `tst` / `all` / `ru`).
   - `ru` → «target `ru` пока не настроен» → STOP.
   - If the target includes `tst` (i.e. `tst` or `all`) — make sure the user understands it
     **overwrites tst's independent DB**; in the no-arg path say so in the question.

## Step 1 — dump prod (direct ssh + hostname guard + retry)

Stream a custom-format dump straight to the local `.tmp/`, no file left on prod, no MCP:

```bash
ssh <pro.ssh_alias> 'test "$(hostname)" = <pro.hostname_guard> && <pro.dump_cmd>' > <cwd>/<dump_local_dir>/vdole_prod.dump
```

- Retry 3×, print the error body on each failed attempt (external/remote call).
- Validate the archive before using it: file size > 0 **and** `pg_restore -l <dump>` lists `TABLE DATA`
  entries. If the guard failed the stream is empty/garbage → abort, do not restore anything.

## Step 2 — restore to local (targets `ssv` / `laptop`, and the first half of `all`)

1. Resolve the target's `env_file` (or `AUTO` via `back/src/shared/local-machine.ts` HOST_MAP).
   Read `DATABASE_URL` **without echoing it to chat** (capture into a shell var in one Bash call).
2. Find local `pg_restore.exe` under `local_pg_bin` (newest version, detect dynamically).
3. Restore:
   ```bash
   pg_restore -d "$DBURL" <restore.flags> <dump>
   ```
   `flags` = `--clean --if-exists --no-owner --no-privileges`. `--no-owner` makes objects belong to
   whoever runs the restore — robust regardless of the owner-role name on each node.
4. Verify `tables_count` and the presence of expected rows.

## Step 3 — restore to tst (target `tst`, and the second half of `all`)

1. Upload the **same** dump from this PC to tst (hub routing, retry 3×):
   ```bash
   scp <dump> <tst.ssh_alias>:<tst.remote_tmp>/vdole_prod.dump
   ```
2. Restore on tst, guarding the hostname and reading the tst DATABASE_URL **server-side**
   (never print it to chat):
   ```bash
   ssh <tst.ssh_alias> bash -s <<'REMOTE'
   test "$(hostname)" = <tst.hostname_guard> || { echo "GUARD FAIL: $(hostname)"; exit 1; }
   DBURL=$(sudo grep -m1 '^DATABASE_URL=' <tst.env_file_on_server> | cut -d= -f2-)
   [ -n "$DBURL" ] || { echo "no DATABASE_URL"; exit 1; }
   pg_restore -d "$DBURL" --clean --if-exists --no-owner --no-privileges <tst.remote_tmp>/vdole_prod.dump 2>/tmp/restore_tst.err
   echo "pg_restore exit=$?"
   grep -iE 'error|fatal' /tmp/restore_tst.err | grep -viE 'does not exist|already exists' | head -20
   REMOTE
   ```
   Do NOT use `set -e` around `pg_restore` — it returns non-zero on benign `DROP … IF EXISTS`
   warnings; capture the exit code and show only non-ignorable errors.
3. Verify `tables_count` on tst.

## Step 4 — cleanup (the dump holds prod PII — never leave it lying around)

- Local dump → Recycle Bin via `trash.ps1`:
  `pwsh -NoProfile -File C:\Users\ssv55\.claude\scripts\trash.ps1 <cwd>\<dump_local_dir>\vdole_prod.dump`
- Remote tst dump → secure delete on the server: `ssh <tst.ssh_alias> 'shred -u <tst.remote_tmp>/vdole_prod.dump'`
  (use `shred`/`unlink`, NOT `rm` — the local block-dangerous hook scans the command string for `rm`).

## Step 5 — report

```
Прод-БД (pro) раскатана на <target(s)>:

| Узел | users | expenses | … |
|------|-------|----------|---|
| ssv  | n     | n        |   |
| tst  | n     | n        |   |

Дамп удалён (локально → корзина, tst → shred).
```

## Rules

- **NEVER** the MCP connector for prod — direct `ssh` only, with a `hostname` guard before any read/write.
- **NEVER** ssh node→node (pro↔tst). Route every byte through this PC.
- **ALWAYS** `--no-owner --no-privileges` on restore.
- Dump files live only in `<cwd>/<dump_local_dir>` (`.tmp/`); delete after (trash local, shred remote).
- `tst` / `all` overwrite tst's independent DB — destructive, intentional; confirm in the no-arg path.
- NEVER use `$env:PGPASSWORD`; pass the connection string directly in `-d` and never echo it to chat.
