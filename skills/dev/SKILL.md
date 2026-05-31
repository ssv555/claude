---
name: dev
description: Manage developers on personal moscow_my server (Linux users + claude-runner isolation + per-dev PG database + per-dev nginx dev-stand + bare git mirror to GitHub). Chief-only skill. Use when user says "/dev", "/dev help", "/dev list", "/dev <alias>", "/dev add", "/dev del <alias>", "/dev sync-skills", "/dev bootstrap". Also entry-point docs for "/dev-merge <alias|sha>", "/dev-changelog <sha>", "/dev-sessions-analyze <alias>".
model: sonnet
allowed-tools: Bash(*), Read(*), Write(*), Edit(*)
---

# dev

Изолированные dev-среды на `moscow_my`: у каждого свой Linux-юзер, PostgreSQL DB, HTTPS-стенд `https://dev-<alias>.it-joy.ru`, блок портов. Claude бежит **как сам dev** (не setuid); OAuth-токен shared через `webdev` user. Push-proxy git-зеркало в GitHub через bot-аккаунт `ssv-bot` (login `ssv555ssv`) → `ssv555/vdole`.

## Status block

В начале выполнения распечатать:

```
SKILL:  dev
MODEL:  sonnet
```

## Доступ — только шеф

ВСЕГДА проверить chief-identity ПЕРЕД любым действием:

```powershell
if (-not (($env:USERNAME -eq 'ssv555') -or ($env:COMPUTERNAME -eq 'PC-SKY'))) {
    Write-Error "Forbidden: chief-only skill"
    exit 1
}
```

## Команды

| Команда | Действие |
|---|---|
| `/dev help` (`-h`, `--help`) | Краткая справка (прямой вывод без SSH) |
| `/dev` или `/dev list` | Таблица всех dev'ов: alias, created_at, last activity, session count, home size |
| `/dev <alias>` или `/dev show <alias>` | Детали по одному dev'у |
| `/dev add <alias> <repo> <full_name>` | Полностью авто-провизия: SSH-ключ, Linux-юзер, nginx+cert, PG role+DB, .env из template, bun install. Пример: `/dev add alx vdole "Alex Smirnov"` |
| `/dev del <alias>` | Подтверждение → kill → tar архивов → drop DB+role+nginx+cert → `userdel -r` + удаление SSH-ключа с PC |
| `/dev ssh block <alias>` | Временно отключить SSH-логин: `mv authorized_keys → .blocked` + `pkill -KILL -u <alias>` (кикнуть активные сессии) |
| `/dev ssh unblock <alias>` | Восстановить SSH-логин: `mv authorized_keys.blocked → authorized_keys` |
| `/dev sync-skills [<alias>\|all]` | Пересинхрон allowlisted скилов в `/opt/claude-shared/skills/` |
| `/dev bootstrap` | Ручной запуск bootstrap (обычно авто при первом `add`) |
| `/dev-merge <alias>` | Список всех незамердженных веток дева (sha / branch / дата / commits / diff) |
| `/dev-merge <sha>` | Смерджить конкретную ветку по HEAD sha (из TG-нотификации). sha-pin check: если ветка ушла вперёд — warning + выбор |
| `/dev-changelog <sha>` | Анализ ветки по sha: Technical changes (backend/frontend/DB) + Business changes (что изменилось для пользователя/бизнеса) |
| `/dev-sessions-analyze <alias>` | Анализ Claude Code сессии дева: 10 метрик качества AI-использования + вовлечённости (test rate, AI corrections, active time, ownership signs, etc). Отчёт MD в `D:\Data\Documents\Programming\Projects\WEB\VDole\.docs\dev\sessions\`. Справка: `cat ~/.claude/skills/dev-sessions-analyze/METRICS.md` |

## Workflow — диспетчер

### `help` — обрабатывается НАПРЯМУЮ, без `dev.ps1`

Если аргумент `help`, `-h` или `--help` — **не вызывай `dev.ps1`, не делай Bash-вызовов**. Просто выведи таблицу команд из раздела «Команды» выше прямо в чат. Никаких SSH, никакого sync.

### Все остальные команды — через `dev.ps1`

```powershell
& 'C:\Users\ssv55\.claude\skills\dev\dev.ps1' <subcommand> [args]
```

Диспетчер на PC шефа делает:
1. `Assert-Chief` — проверка identity
2. `Sync-LibToServer` — `scp -r` всего `lib/` → `/opt/dev-skill/`
3. `Ensure-Bootstrap` — если маркер `/opt/dev-skill/.bootstrap-ok` отсутствует → bootstrap-server.sh
4. SSH → исполняет соответствующий `lib/*.sh`
5. Обновляет локальные метаданные (`~/.claude/developers/<alias>/`)

Интерактив — через `~/.claude/scripts/dialog.ps1` (AskUserQuestion не работает в subagents).

## SSH-конфигурация

Host alias `moscow_my` в `~/.ssh/config` (root@195.2.75.212:53847).

## Bootstrap — однократный, идемпотентный

`lib/bootstrap-server.sh`. Каждый шаг проверяет состояние и skip'ает если уже сделано:

1. `webdev` (UID 1600, shell `/bin/bash`, HOME `/var/lib/webdev`) — auth-holder. После bootstrap chief один раз делает OAuth: `sudo -u webdev -i; claude` → `/var/lib/webdev/.claude/.credentials.json` (640 webdev:webdev). `/dev add` копирует в HOME каждого дева. **Shell `/bin/bash` обязателен** — Anthropic отшивает `nologin`-аккаунты. **UID >=1000 обязателен** — Anthropic отшивает системные UID.
2. `git-mirror` (system, nologin) + группа `developers` + sshd AllowGroups `developers`
3. **Filesystem isolation ACLs** — `setfacl` блокирует `developers` от `/var`, `/backup`, `/snap`, `/media`, `/mnt`, `/cdrom`, `/opt/{certbot,containerd,dev-skill,qdrant}`; traverse-only на `/home`, `/opt`, `/srv`, `/srv/git`. **Exception:** `g:developers:--x` на `/var`, `/var/lib`, `/var/lib/webdev` + `:r-x` на `/var/lib/webdev/.claude` — узкий traverse к креды webdev (всё остальное в /var остаётся блокированным)
4. **SFTP блок + audit** — `02-developers-no-sftp.conf`: `Match Group developers / Subsystem sftp /bin/false` (WinSCP/scp падают, shell работает). `03-sftp-audit.conf`: `-l INFO -f AUTH` для прочих SFTP.
5. **`/etc/hosts` — Anthropic IPv4 force** — 14 anthropic-доменов прибиты к `160.79.104.10`. Зачем: wg0 туннель маршрутизирует только IPv4 → Amsterdam. IPv6 (AAAA) уходит direct с moscow IP → Anthropic geo-block 403.
6. Claude CLI в `/opt/claude/` через `bun install -g`
7. `/opt/claude-shared/` — allowlisted скилы, dev-CLAUDE.md, codex.md, DEV_GUIDE.md, memory/
8. `/usr/local/bin/claude` — **plain symlink** на `/opt/claude/bin/claude` (без setuid wrapper). Дев запускает claude **как самого себя** (UID 1002 = spc).
9. Bare repo `/srv/git/VDole.git` + хуки + origin GitHub
10. Hooks dir + config + HEAD — `g-w` (девы НЕ переписывают)
11. `/home/git-mirror/.ssh/id_ed25519` (фингерпринт `NZ5QUSFA...`) — бэкап ключа из `D:\Data\Backup\Ubuntu-Servers\moscow_my\keys-self\git-mirror\`
12. `mirror-push.sh` + systemd `vdole-mirror.service` + `vdole-mirror.path` (inotify) + sudoers
13. **Daily 06:00 cleanup** — `dev-services-cleanup.sh` + `dev-services-cleanup.timer` убивает все процессы на портах 40001-49999

Bootstrap триггерится автоматически при первом `/dev add`. Маркер `/opt/dev-skill/.bootstrap-ok`. Можно запустить вручную: `/dev bootstrap` (идемпотентно — безопасно перезапускать после правок lib/).

**После bootstrap — ОДИН РАЗ:** `sudo -u webdev -i; claude` → пройти OAuth в браузере → выйти. Без этого `/dev add` будет копировать пустой credentials.json и дев получит TUI с просьбой login.

### Bootstrap-extras (с 2026-05-30)

- **Custom motd** (`/etc/update-motd.d/99-dev-welcome`) — компактный welcome-баннер на каждом login: alias, репо+ветка, статус принятия правил, restart-warn, шорткаты ключевых скилов. Дефолтный Ubuntu-motd погашен через `~/.hushlogin` (создаётся в `add-user.sh`).
- **RULES gate** — `/opt/claude-shared/RULES.md` + `/opt/claude-shared/RULES.version` (SHA-256). Принятие через привилегированный helper `/usr/local/sbin/dev-accept-rules` (sudoers NOPASSWD для %developers). Gate `/etc/profile.d/00-rules-check.sh` блокирует интерактивный shell до приёма. Audit-log: `/opt/claude-shared/audit/rules_acceptances.log` (root 600).
- **Workflow audit-log** — `/usr/local/sbin/dev-audit-log` (sudoers helper). Все `/dev-NN-*` скилы пишут одну строку на действие в `/opt/claude-shared/audit/<YYYY-MM>/<alias>.log` (root 600 — девы не видят чужой работы).
- **Chief notifier** — `/usr/local/sbin/dev-notify-finish` (sudoers helper). `/dev-09-finish` зовёт его → запись в `/opt/claude-shared/audit/finished_branches.log` + TG-сообщение через существующий релэй: TOKEN/CHAT_ID из `/var/backups/.tg_config` (VDOLE_* с fallback на IAMRICH_*), путь `sudo -u www-data ssh -i /var/www/.ssh/id_backup` → amsterdam_my:53847 → `curl api.telegram.org` (fallback amsterdam_grey:53847). Тот же механизм, что у `/usr/local/bin/vdole-tg-forward.sh` и deploy-pipeline'а — никаких новых секретов / endpoint'ов / IP-allowlist'ов. Креды отсутствуют → log-only.

## `/dev add <alias> [<repo>]` — полный flow

При указании `<repo>` — полностью авто-настроенная среда. Без `<repo>` — только Linux-юзер.

### ⚠️ Ручная подготовка ПЕРЕД `/dev add <alias>`

Шеф ОБЯЗАН зарегистрировать OAuth redirect URI для нового стенда во всех провайдер-консолях, иначе OAuth-flow упадёт на проверке callback'а:

- Google Cloud Console → OAuth 2.0 Client → Authorized redirect URIs → `+ https://dev-<alias>.it-joy.ru/auth/google/callback`
- VK Dev (id.vk.com) → приложение → Redirect URIs → `+ https://dev-<alias>.it-joy.ru/auth/vk/callback`
- Yandex OAuth (oauth.yandex.ru) → приложение → Callback URI → `+ https://dev-<alias>.it-joy.ru/auth/yandex/callback`
- MailRu Tech (o2.mail.ru) → приложение → Redirect URL → `+ https://dev-<alias>.it-joy.ru/auth/mailru/callback`

Уже зарегистрированные стенды (на 2026-05-27): `dev-alx.it-joy.ru`, `dev-spc.it-joy.ru`.

### Env template — `.env.outstaffers`

Шаблон environment'а для девов хранится локально на PC шефа:
- **VDole:** `d:\Data\Documents\Programming\Projects\WEB\VDole\.env.outstaffers`

Файл генерится скриптом `_infra/scripts/dev/make-env-outstaffers.ps1` (под SVN) из шефского `.env.development`:
- Per-dev placeholders: `{{ALIAS}}`, `{{PORT_API}}`, `{{PORT_HMR}}`, `{{DB_PASSWORD}}`, `{{JWT_SECRET}}`, `{{COOKIE_SECRET}}`, `{{SESSION_SECRET}}`, `{{BOT_SECRET}}`, `{{DATA_ENCRYPTION_KEY}}`, `{{EMAIL_WEBHOOK_SECRET}}`
- DUMMY-замена для production-секретов: `BOT_TG_TOKEN`, `BOT_MAX_TOKEN`, `SMSAERO_API_KEY`, `SMSRU_API_ID`, `UNISENDER_GO_API_KEY`, `*_CLIENT_SECRET` (Google/VK/Yandex/MailRu), `YANDEX_SMARTCAPTCHA_SERVER_KEY` — дев получает DUMMY по умолчанию
- DROPPED: `SMTP_TUNNEL_PORT` (атавизм после миграции на REG.ru + Unisender Go)
- ADDED: `DISABLE_BOTS=true` — TG/MAX боты в dev-env спят (не делают long-polling) → нет 409 Conflict с прод-ботом шефа
- KEPT: публичные client_id, VITE_* флаги, ADMINS, статические порты, *_FROM_EMAIL
- БЕЗ комментариев и пустых строк (защита от утечки секретов через комменты шефа)

Если деву нужны реальные креды (OAuth, SMS, Email, реальный test-bot) — шеф передаёт через TG и дев патчит через claude (claude-runner может писать в `.env.development`).

При `/dev add <alias> vdole` диспетчер `dev.ps1`:
1. Копирует локальный `.env.outstaffers` → `/opt/dev-skill/.env.development` (root:root 600)
2. `add-user.sh` рендерит шаблон через `perl -pe` → подставляет per-dev значения
3. Результат пишется в `/home/<alias>/projects/vdole/.env.development` (claude-runner:claude-runner 600 — дев не читает)

### Auto-flow

1. **Chief PC:** ssh-keygen → `D:\Data\Backup\Ubuntu-Servers\moscow_my\keys-client\<alias>\id_ed25519`
2. **Chief PC:** `Get-NextPortBlock` сканит `/etc/nginx/conf.d/dev-*.it-joy.ru.conf`, ищет следующий свободный 10-блок в `40001..49991`. Шаг **10** — до 100 девов.
3. **Chief PC:** `New-NginxConfForDev` — генерит HTTP-stub conf → `certbot --webroot` → full HTTPS conf из `lib/nginx-dev-template.conf` (placeholders `{{ALIAS}}`, `{{PORT_API}}`, `{{PORT_HMR}}`) → nginx reload
4. **Server (`add-user.sh`):**
   - `adduser --disabled-password` + `usermod -aG developers <alias>` + `usermod -aG webdev <alias>` (read /var/lib/webdev/.claude/creds) + `usermod -aG <alias> ssv` (chief read access without sudo)
   - `~/.ssh/authorized_keys` (pub-half from chief)
   - `~/.bashrc` — `export TERM=xterm-256color` + `export LC_ALL=en_US.UTF-8` (Termius шлёт `TERM=vt100` → ломает TUI) + auto-cd в `~/projects/<repo>` при interactive login
   - `~/.claude/` (**<alias>:<alias> 750** — дев сам owner, claude бежит как он) + симлинки read-only на `/opt/claude-shared/` (skills/CLAUDE.md/codex.md/DEV_GUIDE.md)
   - `~/.claude/memory/` — per-dev директория, seeded `cp -a /opt/claude-shared/memory/.` (каждый дев пишет в свою память изолированно)
   - `~/.claude/.credentials.json` — **копия** `/var/lib/webdev/.claude/.credentials.json` (640 webdev:webdev). Claude НЕ принимает symlink на чужой файл — поэтому `cp`, не `ln`. Refresh-tokens у каждого дева расходятся со временем; bootstrap-auth shared
   - `~/.claude.json` — копия `/var/lib/webdev/.claude.json` (global settings/state, нужен для распознавания валидной сессии)
   - `~/projects/` (`<alias>:<alias>` 755)
   - git config user.name/user.email
5. **Server (clone + tweak):**
   - `git clone /srv/git/<repo>.git ~/projects/<repo>` (origin = bare local path)
   - `chown -R <alias>:<alias>` на `~/projects/<repo>` — дев сам owner
6. **Server (PostgreSQL):**
   - `CREATE ROLE user_<alias>` с **рандомным 32-char паролем**
   - `CREATE DATABASE <repo>_<alias> TEMPLATE <repo>` (fallback empty DB при активных коннектах)
   - `GRANT ALL ON DATABASE`
7. **Server (.env.development):**
   - Полный env: SERVER_PORT/FRONT_PORT/BOT_TG_PORT/BOT_MAX_PORT (из port-блока)
   - DATABASE_URL с реальным паролем user_<alias>
   - JWT_SECRET / COOKIE_SECRET / SESSION_SECRET — рандом 64-char
   - PUBLIC_BASE_URL = `https://dev-<alias>.it-joy.ru`
   - OAuth/SMS/SMTP/Bot tokens — DUMMY (шеф докинет real-creds через secure channel если деву нужны интеграции)
   - **Perms: 600 <alias>:<alias>** — дев читает (claude/bun запущены как сам dev). TODO: build/deploy isolation — split в `~/projects/<repo>` (DUMMY) и `~/projects/<repo>-www` (REAL, owned webdev) — см. `docs/todo/`
8. **Server:** `bun install` от имени дева
9. **Server (`add-user.sh` шаг 7 — README onboarding для дева):**
   - Рендерит `lib/README.template.md` (плейсхолдеры `{{ALIAS}}`, `{{HOST_IP}}`, `{{SSH_PORT}}`, `{{PORT_*}}`, `{{DB_NAME}}`, `{{DB_USER}}`, `{{REPO_NAME}}` и т.д.) → `/home/<alias>/README.<ALIAS_UPPER>.md` (`<alias>:<alias>` 644 — дев читает свободно). Sanity-check на нерасширенные `{{}}` → warn в лог. **Не содержит пути к private key шефа** (только параметры для Termius: host/port/user).
10. **Chief PC:**
    - `~/.claude/developers/<alias>/info.json` (alias/email/fp/ssh_key_path/created_at/...)
    - `~/.claude/developers/<alias>/onboarding.md` — текст для пересылки деву
    - Append row в `D:\Data\Backup\Ubuntu-Servers\moscow_my\SSH_KEYS_INVENTORY.md`
    - `/dev show <alias>` отображает абсолютный `ssh key path` + отдельный чистый блок для копирования в Termius

## `/dev del <alias>` — полный flow

1. Подтверждение через `dialog.ps1` (введи alias)
2. **Server (`del-user.sh`):**
   - `pkill -KILL -u <alias>`
   - tar 4 архивов в `/tmp/dev-del-<alias>-<date>/`: claude-projects, claude-sessions, projects (excluding build dirs), home rest
   - Activity dump (`last` + `journalctl _UID=`)
   - PostgreSQL: drop DBs owned by `user_<alias>` (terminate active connections first) → `DROP ROLE user_<alias>`
   - `userdel -r`
3. **Chief PC:**
   - `Remove-NginxConfForDev` — nginx conf удалён + `certbot delete` + webroot снят + reload
   - scp архивов в `~/.claude/developers/<alias>/_archive/<date>/`
   - info.json: `archived_at` + `status: archived`
   - `SSH_KEYS_INVENTORY.md`: row `REVOKED`

## Port allocation — шаг 10

```
spc → 40001 (API), 40002 (HMR), 40003 (TG bot), 40005 (MAX bot)  → block 40001-40010
alx → 40011, 40012, 40013, 40015  → block 40011-40020
... → +10 per dev
```

`Get-NextPortBlock` сканит `/etc/nginx/conf.d/dev-*.it-joy.ru.conf`, выбирает следующий свободный блок. Диапазон 40001..49991 = до **100 девов**.

## Daily cleanup — 06:00 MSK

Защита от забытых `bun run dev`:

- systemd timer `dev-services-cleanup.timer` (`OnCalendar=*-*-* 06:00:00 Persistent=true`)
- запускает `/opt/dev-skill/dev-services-cleanup.sh` под root
- скрипт находит все процессы listening на 40001-49999 через `ss`, отправляет SIGTERM, ждёт 5s, SIGKILL стойким
- лог в `/var/log/dev-services-cleanup.log`
- **НЕ убивает** SSH сессии, bash, claude — только port-listening dev-серверы

Manual force-cleanup: `sudo systemctl start dev-services-cleanup.service`

## Allowlist скилов

`C:\Users\ssv55\.claude\developers\skills_allowlist.json` — single source of truth.

Sync через `/dev sync-skills` пишет в `/opt/claude-shared/skills/` (root-owned read-only).
Дев'ам отдаются (актуально на 2026-05-30):
- `pre-deploy-check`, `pre-deploy-autotests`
- `version-up`, `session-archive`
- `dev-info`
- `dev-00-start` — начать задачу (pull main + новая ветка)
- `dev-01-status` — где я (ветка, коммиты, dirty)
- `dev-05-commit` — коммит (с branch guard, один таск = один коммит)
- `dev-07-commit-push` — коммит + push (один таск = один push)
- `dev-08-reset` — rebase на свежий main
- `dev-09-finish` — финал (pre-deploy + push + уведомление шефа)

Старые имена `dev-commit/dev-push/dev-reset` упразднены 2026-05-30 — заменены номерными для отображения порядка в workflow.

**Chief-only скилы — НЕ синкаются на сервер** (в `_excluded_intentionally`, девы их не видят):
- `dev` — этот самый диспетчер
- `dev-merge` — review + merge ветки дева в main
- `dev-changelog` — анализ diff'а dev-ветки vs main (Technical + Business changes)
- `dev-sessions-analyze` — анализ Claude Code сессии дева на 10 метрик (prompt quality, AI corrections, test rate, active time, ownership signs, etc); справка в `~/.claude/skills/dev-sessions-analyze/METRICS.md`

## Раскладка ФС на сервере

```
/opt/claude/                            root:root 755                    ← бинарь claude
/opt/claude-shared/                     root:root 755                    ← общая конфигурация
  skills/                               (allowlist'ом)
  CLAUDE.md                             dev-версия (только code quality + workflow)
  codex.md, DEV_GUIDE.md, memory/
  RULES.md                              root:root 644                    ← обязательные правила
  RULES.version                         root:root 644                    ← SHA-256 текущего RULES.md
  rules_acceptances/                    root:root 755                    ← <alias>__<hash>.flag (root 644)
  audit/                                root:root 750                    ← дев не читает
    rules_acceptances.log               root:root 600                    ← кто/когда/откуда принял правила
    finished_branches.log               root:root 640                    ← /dev-09-finish events (для шефа/notifier)
    <YYYY-MM>/<alias>.log               root:root 600                    ← per-dev workflow audit
/opt/dev-skill/                         root:root 755                    ← server-side скрипты
  bootstrap-server.sh, add-user.sh, del-user.sh, list-users.sh
  mirror-push.sh, vdole-mirror.{service,path}
  pre-receive.sh, post-receive.sh
  dev-services-cleanup.{sh,service,timer}
  nginx-dev-template.conf
  README.template.md, AGREEMENT.template.md, RULES.template.md
  99-dev-welcome                        (→ /etc/update-motd.d/99-dev-welcome)
  00-rules-check.sh                     (→ /etc/profile.d/00-rules-check.sh)
  dev-accept-rules.sh                   (→ /usr/local/sbin/dev-accept-rules)
  dev-audit-log.sh                      (→ /usr/local/sbin/dev-audit-log)
  dev-notify-finish.sh                  (→ /usr/local/sbin/dev-notify-finish; читает /var/backups/.tg_config)
  dev-shared-CLAUDE.md, codex.md, DEV_GUIDE.md, memory/
  .bootstrap-ok

/usr/local/sbin/dev-accept-rules        root:root 750                    ← privileged helper для приёма правил
/usr/local/sbin/dev-audit-log           root:root 750                    ← privileged helper для workflow audit
/usr/local/sbin/dev-notify-finish       root:root 750                    ← privileged helper для уведомления шефа

/etc/profile.d/00-rules-check.sh        root:root 755                    ← gate: блокирует shell до приёма правил
/etc/update-motd.d/99-dev-welcome       root:root 755                    ← custom motd для девов

/etc/sudoers.d/dev-accept-rules         root:root 440                    ← %developers → dev-accept-rules accept *
/etc/sudoers.d/dev-skills-helpers       root:root 440                    ← %developers → dev-audit-log + dev-notify-finish

/usr/local/bin/claude                   symlink → /opt/claude/bin/claude  ← plain symlink, БЕЗ setuid

/var/lib/webdev/                        webdev:webdev 755                 ← auth-holder (UID 1600, shell /bin/bash, OBLIGATORY: Anthropic refuses nologin/UID<1000)
  .claude/                              webdev:webdev 755 + ACL g:developers:r-x
    .credentials.json                   webdev:webdev 640                 ← master OAuth (один OAuth login chief'ом, потом /dev add копирует в HOME каждого дева)
  .claude.json                          webdev:webdev 600                 ← global settings

/etc/hosts                                                                 ← 14 anthropic-доменов прибиты к 160.79.104.10 (force IPv4 → wg0 → Amsterdam)
/etc/ssh/sshd_config.d/02-developers-no-sftp.conf                          ← Match Group developers: Subsystem sftp /bin/false (WinSCP блок)
/etc/ssh/sshd_config.d/03-sftp-audit.conf                                  ← audit-log SFTP

/home/<dev>/                            <dev>:<dev> 750                   ← plain 750, БЕЗ ACL (sshd StrictModes happy)
  README.md                             <dev>:<dev> 644                   ← onboarding из lib/README.template.md
  AGREEMENT.md                          <dev>:<dev> 644                   ← NDA из lib/AGREEMENT.template.md
  .ssh/                                 <dev>:<dev> 700
  .bashrc                                                                  ← + TERM=xterm-256color + LC_ALL=en_US.UTF-8 + auto-cd projects/<repo>
  .claude.json                          <dev>:<dev> 600                   ← КОПИЯ из /var/lib/webdev/.claude.json (нужно для распознавания валидной сессии)
  .claude/                              <dev>:<dev> 750                   ← дев сам owner (claude бежит как dev)
    skills    → /opt/claude-shared/skills    (read-only symlink)
    CLAUDE.md → /opt/claude-shared/CLAUDE.md
    codex.md, DEV_GUIDE.md               → /opt/claude-shared/... (read-only)
    memory/                             <dev>:<dev> 700                   ← per-dev, seeded из shared
    projects/                           <dev>:<dev> 700                   ← claude пишет conversation data
    sessions/                           <dev>:<dev> 700                   ← claude пишет session metadata
    .credentials.json                   <dev>:<dev> 600                   ← КОПИЯ /var/lib/webdev/...creds (не симлинк — claude ругается). Refresh-tokens расходятся со временем
  projects/                             <dev>:<dev> 755
    <repo>/                             <dev>:<dev>                       ← дев сам owner всех файлов
      .env.development                  <dev>:<dev> 600                   ← дев МОЖЕТ читать (claude/bun бегут как dev). TODO build/deploy isolation

/srv/git/VDole.git/                     root:developers 2775
  hooks/                                root:developers 2755              ← g-w (дев НЕ переписывает pre-receive)
    pre-receive                         блокирует push в protected (кроме не-developers)
    post-receive                        touch /var/spool/vdole-mirror/queue
  config, HEAD, description             g-w (chief-only)

/var/spool/vdole-mirror/                root:git-mirror 770
  queue                                 inotify trigger

/home/git-mirror/                       git-mirror:git-mirror 750
  .ssh/id_ed25519                       git-mirror:git-mirror 600         ← бот ssv555ssv (display ssv-bot)
  .gitconfig                            git-mirror:git-mirror 644         ← safe.directory
  bin/mirror-push.sh                    root:root 755
```

## Filesystem isolation для devs (через ACL)

Дев в группе `developers` НЕ видит:
- `/var`, `/backup`, `/lost+found`, `/snap`, `/media`, `/mnt`, `/cdrom` — full block (exception: `--x` traverse до `/var/lib/webdev/.claude/` для чтения мастер-creds)
- `/opt/{certbot,containerd,dev-skill,qdrant}` — full block
- `ls /home`, `ls /opt`, `ls /srv` — traverse-only (только cd по точному пути)
- `/etc/nginx` (750 root:root)
- Чужие процессы в `ps aux` (`hidepid=invisible` на `/proc`)
- Чужие SSH/auth логи (`/var` blocked)
- SFTP/WinSCP/scp — `Subsystem sftp /bin/false` для group developers
- Чужие `/home/<other>/` (750 owner:owner — group developers попадает в other=0)

Дев МОЖЕТ:
- Читать ВСЁ в собственном `~/` (он сам owner — это его рабочее место)
- Включая `.env.development` (claude бежит как dev → нет другого UID для изоляции). Защита через build/deploy isolation — TODO

## Что НЕ делать

- Не запускать `/dev add`/`del`/`bootstrap` без явного запроса пользователя
- Не читать `/home/<dev>/.claude/.credentials.json` или содержимое архивов
- Не пушить в protected branches через bot-аккаунт — нарушает audit-trail
- Не редактировать allowlist без подтверждения
- Не показывать содержимое SSH private-key и `.env.development` в чате (секреты)

## Зависимости (выполнены 2026-05-27)

1. ✅ SSH-порт мигрирован на 53847
2. ✅ GitHub bot-аккаунт `ssv-bot` (login `ssv555ssv`) создан, приглашён в `ssv555/vdole`
3. ✅ Bot SSH-key (FP `NZ5QUSFA`) добавлен в bot's GitHub SSH settings, бэкап на ПК в `keys-self/git-mirror/`
