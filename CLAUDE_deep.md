# Global Rules — детали (L4)

> **TL;DR.** Ситуативные процедуры, вынесенные из глобального CLAUDE.md ради экономии токенов каждой сессии. Читать по ссылке из ядра, когда наступил соответствующий контекст. Ядро: [CLAUDE.md](CLAUDE.md).
> ⚠️ ~280 строк / ~5k токенов — Grep по нужному разделу, не читать целиком.

## PING BEFORE BROWSER — UNIVERSAL

**Before ANY browser automation (Playwright, WebFetch, `curl` to dev URL), probe the target with a short-timeout HTTP check FIRST. Never fire a `browser_navigate` blind.**

### The rule

1. **Know the ports.** Every project documents its dev ports in `CLAUDE.md` (for VDole: 32001 API, 32002 frontend HMR, etc.). Read them once, cache in this session.
2. **Probe first, navigate second.** Before the first navigate of the session (and again if the server may have died):
   ```bash
   # Prefer a known health endpoint over the root path — it's cheaper and gives an explicit signal
   curl -sS -o /dev/null -w "%{http_code}\n" --max-time 3 http://localhost:<port>/health
   # Fallback: probe root
   curl -sS -o /dev/null -w "%{http_code}\n" --max-time 3 http://localhost:<port>
   ```
   `000` or non-2xx/3xx → server down. For VDole backend `/health` and `/api/health` return `OK` ([back/src/app.ts:185](back/src/app.ts#L185)); frontend HMR on `:32002` has no dedicated health route, probe root.
3. **If down — STOP and ask, don't retry.** Tell the user: *«Dev-сервер на `:PORT` не отвечает. Запусти `<project command>`»*. Don't hammer with 60-second timeouts. Don't try 3 times hoping it starts itself.
4. **If up — proceed with Playwright.** One probe at session start is enough; re-probe only if a navigate fails or after a long idle.
5. **For HTTPS proxy dev URLs** (e.g. `vdole-ssv.it-joy.ru` which nginx-proxies to `:32002`): probe the HTTPS URL with `--max-time 5`, OR probe the underlying local port. Both work; local port is faster.

### Applies to

- Playwright MCP `browser_navigate` to any `localhost:*` or configured dev-host
- WebFetch against dev URLs
- `curl` against dev URLs in scripts/checks

### Does NOT apply to

- Production URLs (always assumed up; if they're down, that's a separate incident)
- Public documentation pages, external APIs with their own SLAs

### Why
(incident 2026-04-22: fired `browser_navigate` blind twice, both timed out at 60s — HMR server was down; a 3s `curl` would have caught it instantly.)

## Windows batch files MUST have CRLF line endings — UNIVERSAL

After editing or writing any `.cmd` / `.bat` file on Windows, ALWAYS verify and restore CRLF line endings (`\r\n`). The `Edit` and `Write` tools save files with LF-only line endings, which silently corrupts batch files — CMD eats the first 1–2 characters of each line and produces bizarre errors like `'tlocal' is not recognized`, `'cp' is not recognized`, `'et' is not recognized` (from `setlocal`, `chcp`, `set`). The file LOOKS fine in a text editor but is broken at runtime.

**Applies to**: `.cmd`, `.bat`, any Windows-only script file. PowerShell (`.ps1`) tolerates LF, so it's not affected, but when in doubt — use CRLF on Windows.

**How to apply after every edit**:

```bash
cd "<project>" && unix2dos <file>.cmd
```

Or if `unix2dos` isn't installed:

```bash
pwsh -nop -c "$p='<file>.cmd'; $c=[IO.File]::ReadAllText($p); $c=$c -replace \"`r`n\",\"`n\" -replace \"`n\",\"`r`n\"; [IO.File]::WriteAllText($p,$c)"
```

Verify after with `od -c <file>.cmd | head -3` — first line must end with `\r \n`, not just `\n`.

**Why**: (incident) LF-only `run_all_update.cmd` made CMD eat the first chars of every command — whole script broken with `'X' is not recognized` errors.

## PowerShell — `pwsh` only, NEVER `powershell` — UNIVERSAL

**Why**: Windows PowerShell 5.1 writes stdout in OEM codepage (cp866 on RU locales, cp1251 elsewhere). The Bash tool reads as UTF-8 → output comes back as garbage (`���  �業�� ��� �믮��塞��`) — unreadable for both Claude and user, debugging blind. Also: 5.1 has broken argument parsing for `-Command "..."` with quoted variables like `$env:USERNAME` (strips the `$env:` prefix). `pwsh` 7+ is UTF-8 by default, modern parser, no surprises.

**How to apply**:

```bash
# ✅ correct
pwsh -NoProfile -Command "Write-Host \"hello $env:USERNAME\""
pwsh -NoProfile -File path\to\script.ps1 arg1 arg2

# ❌ wrong — DO NOT USE
powershell -NoProfile -Command "..."
powershell -nop -c "..."
```

If `pwsh` is genuinely missing on a machine (rare in 2026), STOP and tell the user — don't silently fall back to legacy `powershell`.

(incident 2026-05-28: `powershell -Command` in `/dev add` ate `$env:` → `:USERNAME is not recognized` + cp866 garbage; chief-guard silently mis-passed. `pwsh` would have worked.)

## TODO files — Priority + Difficulty header — UNIVERSAL

Every file in any project's `docs/todo/` (and `docs/suspended/`) MUST begin with a five-line metadata header **in English**, immediately after the H1 title:

```markdown
# <Task title>

**Priority:** Medium
**Difficulty:** 2d, 0h, 0m
**Status:** Pending
**Created:** 2026-05-25
**Owner:** —
```

### `Priority` — six levels, ascending importance

| Level | When to set | What it means for scheduling |
|---|---|---|
| `Suspend` | Idea on hold; may never ship. Waiting on external decision or value is unclear. | Not worked on. The file exists to preserve the thought. If you later disagree — re-prioritise to `Low`+ or move the file to `docs/suspended/`. |
| `Low` | Nice-to-have, minor cleanup, cosmetics, low-impact refactor. | Backlog. Do when convenient or bundled into a nearby rewrite. |
| `Medium` | Worthwhile refactor, obvious tech-debt, improvement that pays off. | Next sprint. Queued but not blocking. |
| `High` | Roadmap feature for the current sprint. Regression on a key flow. Blocks the next goal. | Current sprint. Plan for 1–2 weeks. |
| `Extra` | Pre-launch must-have, critical UX bug, contract/investor commitment with a near deadline. | Within days. Pre-empts unrelated minor work but does not freeze the sprint. |
| `ASAP` | Active security incident, prod down, money leaking, PII leak in progress. | Drop other work. Hour-scale reaction. |

### `Difficulty` — focused effort in `Nd, Nh, Nm`

Always three components, zeros written explicitly. One **day = 8 working hours** (not 24 calendar hours). Examples:

| Estimate | Header value |
|---|---|
| 30 minutes | `0d, 0h, 30m` |
| 2 hours    | `0d, 2h, 0m` |
| Half day   | `0d, 4h, 0m` |
| 1 day      | `1d, 0h, 0m` |
| 2.5 days   | `2d, 4h, 0m` |
| 1 week     | `5d, 0h, 0m` |
| 2 weeks    | `10d, 0h, 0m` |

Why fixed three-field format: machine-parseable with a single regex (`(\d+)d, (\d+)h, (\d+)m`), eye-parseable in tables, no ambiguity between "1d" meaning calendar day vs work day.

If the estimate is a range, write the **upper bound** (your worst-case finish). Add a body line if the range is wide: `Estimate range: 2d–5d, upper bound shown.`

### `Status`

| Value | Meaning |
|---|---|
| `Pending` | Not started. |
| `In Progress` | Actively worked on; expect a working branch or PR. |
| `Blocked` | Waiting on external decision or access — name the blocker in the body. |
| `Done` | Move the file to `docs/archive/todo/` per project conventions. |

### `Created` / `Owner`

- `Created` — `YYYY-MM-DD` date the task was filed. Never use relative dates ("yesterday", "last week").
- `Owner` — full name or short alias (`ssv`, `kirill`); use `—` if unassigned.

### Why English

The header is a triage signal for both future AI sessions and any returning developer. Russian field labels split that signal — an AI re-entering the project after weeks should triage at a glance without translation. The body of the file can be in whichever language fits the audience; only the header is fixed in English.

### Filename convention

TODO file names encode priority and difficulty as a sortable prefix so the file explorer is itself a triage view (sort by name → highest priority on top):

```
<priority>_<difficulty>__<slug>.md
```

- `<priority>` — `p0` … `p5`, mapping to the words in the header table below.
- `<difficulty>` — same `Nd_Nh_Nm` as the header body, **underscores instead of commas and spaces**.
- `__` (double underscore) separates metadata from slug.
- `<slug>` — `snake_case` lowercase, no spaces, descriptive of the task. ASCII letters, digits, underscores only.
- Extension always `.md`.

| Header `Priority` | Filename prefix |
|---|---|
| `ASAP`    | `p0` |
| `Extra`   | `p1` |
| `High`    | `p2` |
| `Medium`  | `p3` |
| `Low`     | `p4` |
| `Suspend` | `p5` |

Examples:

```
p0_0d_2h_0m__fix_session_token_leak.md
p1_5d_0h_0m__pre_launch_response_canon.md
p3_2d_0h_0m__ui_form_field.md
p5_0d_4h_0m__investigate_redis_streams_option.md
```

**The filename prefix and the header values MUST stay in sync.** When you bump `Priority: High` → `Extra` in the header, rename the file `p2_*` → `p1_*` in the same edit. Same for `Difficulty`.

### Archive — strip the prefix on move

When a task completes (or is intentionally killed and you move to `docs/archive/todo/`), **drop the `<priority>_<difficulty>__` prefix**. The archive cares about *what* was done, not its old urgency or estimate.

```
docs/todo/p2_3d_0h_0m__api_response_canon.md
  → after merge, mv to:
docs/archive/todo/api_response_canon.md
```

Same rule for `docs/suspended/` moves (intentional kills): strip the prefix.

The estimate and priority at completion time are still preserved in the file's header inside — the body stays untouched on archive. Only the filename changes.

### Application

- **New TODO files** — header AND filename prefix are mandatory.
- **Existing files without the header / prefix** — backfill on the next touch (the session where you edit the file for unrelated reasons). Do NOT batch-rewrite the whole `docs/todo/` directory just for headers — but DO rename via `git mv` when you do touch a file, so history is preserved.
- **Skill / agent automation** — any skill that creates TODO files (e.g. session-archive flows) must emit the header AND name the file with the prefix.

### `Suspend` vs `docs/suspended/`

Both mean "not now", but differ in expected lifecycle:

- `Priority: Suspend` in `docs/todo/` = on hold, **may revive** when blocker clears.
- File moved to `docs/suspended/` = decision recorded that this is **parked indefinitely / abandoned**; revival requires a new TODO file.

When in doubt, prefer `Priority: Suspend` first; only move to `docs/suspended/` after an explicit decision to kill.

## Claude Code Session Storage — UNIVERSAL

Claude Code stores session data locally. Use this to extract token usage, durations, and other metadata.

### File locations

| What | Path | Content |
|---|---|---|
| Session meta | `~/.claude/sessions/{pid}.json` | `{ pid, sessionId, cwd, startedAt, kind, entrypoint }` |
| Session messages | `~/.claude/projects/{project-slug}/{sessionId}.jsonl` | One JSON object per line — messages, tool calls, attachments |
| Subagent messages | `~/.claude/projects/{project-slug}/{sessionId}/subagents/agent-*.jsonl` | Same format, one file per subagent |

`{project-slug}` is the CWD path with separators replaced by `--` (e.g. `d--Data-Documents-Projects-WEB-VDole`).

### Discovering the current session

```bash
# Most recent session JSONL for this project
SESSION_JSONL=$(ls -t ~/.claude/projects/*"$(basename "$(pwd)")"/*.jsonl 2>/dev/null | head -1)
SESSION_ID=$(basename "$SESSION_JSONL" .jsonl)
SUBAGENTS_DIR="$(dirname "$SESSION_JSONL")/$SESSION_ID/subagents"
```

### Token usage

Each line with `type: "assistant"` contains `message.usage`:
```json
{ "input_tokens": N, "cache_creation_input_tokens": N, "cache_read_input_tokens": N, "output_tokens": N }
```

**Aggregation script** (bun, works for any JSONL file):
```bash
bun -e "
const fs=require('fs');
const f=process.argv[1];
const lines=fs.readFileSync(f,'utf-8').split('\n').filter(Boolean);
let inp=0,cc=0,cr=0,out=0,n=0;
for(const l of lines){try{const o=JSON.parse(l);if(o.message?.usage){const u=o.message.usage;inp+=u.input_tokens||0;cc+=u.cache_creation_input_tokens||0;cr+=u.cache_read_input_tokens||0;out+=u.output_tokens||0;n++}}catch{}}
console.log(JSON.stringify({messages:n,input:inp,cache_create:cc,cache_read:cr,output:out,total:inp+cc+cr+out}))
" "$FILE_PATH"
```

To sum main session + all subagents, run the script on each JSONL and sum the totals.

### When to use

- **Session archiving** (`/session-archive`) — report total tokens in the archive file
- **Orchestrator finalization** (`final.md`) — report per-subagent and total tokens
- **User asks about token usage** — extract from the current session's JSONL

## Personal Infra — moscow_my / amsterdam_my / amsterdam_grey

Docs / canonical source of scripts / snapshots for the **user's personal servers**
(not VDole production) live in:

```
D:\Data\Backup\Ubuntu-Servers\INFRA\
```

Structure: `INFRA/servers/<server-alias>/{docs,snapshots,scripts}/`. Entry point per server —
`servers/<alias>/README.md`. For moscow_my specifically (VPN relay for the home PC,
AmneziaWG + VLESS legacy + AS13335-expanded wg0 → amsterdam) open
`D:\Data\Backup\Ubuntu-Servers\INFRA\servers\moscow_my\README.md`.

**Claude's INFRA access rules** are strict, written in
`D:\Data\Backup\Ubuntu-Servers\INFRA\CLAUDE.md`. Key point: Claude may
create/edit/delete **only inside INFRA/**; never touch anything higher up the tree
(`D:\Data\Backup\Ubuntu-Servers\`, `D:\Data\Backup\`, etc.). This includes the runtime
script copies in `Ubuntu-Servers\moscow_my\awg\` — those hold working copies with the
client's private keys; the user syncs them himself.

### SVN repository

The whole `Ubuntu-Servers\` tree is a **Subversion working copy** (own SVN server on
the user's `pc-sky` box), not git:

- **URL:** `https://pc-sky/svn/Backup/Ubuntu-Servers` (repo root `https://pc-sky/svn/Backup`).
- **Scope:** versions the entire `Ubuntu-Servers\` tree, not just `INFRA\` — but Claude's
  edit rights stay confined to `INFRA\` (see access rules above).
- **Ignore policy:** `svn:global-ignores` set on the WC root keeps the repo **text-only** —
  scripts, configs, keys/certs in PEM/text form, systemd units, `.md`/`.json`/`.sql`/etc.
  All binaries are excluded: archives (`*.gz/tgz/tar/zip/7z/...`), images, fonts, `*.so`,
  `*.db`, `*.der/p12/pfx`, plus regenerable junk (`node_modules`, `dist`, caches, `.idea`,
  logs, `*.bak`, `*~`). Rationale: binary blobs in SVN bloat every revision (no deltas) and
  kill `diff`/`blame`. **Do not add binaries** — extend `svn:global-ignores` instead.
- **SVN CLI:** `svn.exe` available via scoop (`C:\Users\ssv55\scoop\shims\svn.exe`, SlikSvn 1.14.5). Claude can commit directly: `svn commit "<path>" -m "message"`. TortoiseSVN GUI also works as fallback. Previously thought CLI was absent — outdated, ignore any such notes.
- **Commits:** SVN commit goes to the user's own server. Don't `svn commit` unprompted;
  on explicit request use `svn add --force .` (respects ignores) then `svn commit`.

Otherwise SVN is initialised and managed by the user.

### VPN exit check — `check-vpn.cmd`

Client-side diagnostic for the user's PC. Probes 14 services (5 RU + 9 INTL), parses Cloudflare `cf-ray` PoP, classifies external IP against known infra ranges, flags INTL traffic leaking through RU PoP. Server-agnostic — usable with any active tunnel (moscow_my relay, direct to amsterdam_my/amsterdam_grey, no-VPN baseline). Use it whenever VPN routing needs verification across projects.

- Canonical: `D:\Data\Backup\Ubuntu-Servers\INFRA\scripts\check-vpn\` (`check-vpn.cmd` + `check-vpn.ps1` + `README.md` + `logs/`).
- Runtime: separate copy on user's PC, synced by user (location varies per machine).
- Run: double-click `check-vpn.cmd`; per-run log written to `logs/check-vpn_YYYY-MM-DD_HHmmss.log`.

## Developer skills allowlist

Devs running on `moscow_my` (managed via `/dev` skill) get a curated, shared set of skills — NOT the chief's full skill list. Source of truth:

- **Allowlist:** [`developers/skills_allowlist.json`](developers/skills_allowlist.json) (chief PC) — JSON with `global` (skills synced into `/opt/claude-shared/skills/`) and `local_per_project` (skills bundled into specific project clones on the server).
- **Sync command:** `/dev sync-skills` — rsync allowlisted skills from `~/.claude/skills/` to the server's `/opt/claude-shared/skills/`. Runs after every `/dev add` and on demand.
- **Server runtime:** every dev's `~/.claude/skills` is a root-owned symlink to `/opt/claude-shared/skills/`; devs cannot add skills locally (write blocked by the setuid `claude` wrapper).

Edit `skills_allowlist.json` then `/dev sync-skills` to propagate. Removing a skill from the list and re-running sync deletes it from `/opt/claude-shared/skills/` on next sync.
