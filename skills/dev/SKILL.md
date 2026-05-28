---
name: dev
description: Manage developers on personal moscow_my server (Linux users + claude-runner isolation + per-dev PG database + per-dev nginx dev-stand + bare git mirror to GitHub). Chief-only skill. Use when user says "/dev", "/dev help", "/dev list", "/dev <alias>", "/dev add", "/dev del <alias>", "/dev sync-skills", "/dev bootstrap".
model: sonnet
allowed-tools: Bash(*), Read(*), Write(*), Edit(*)
---

# dev

Управление dev'ами на `moscow_my`. Полностью изолированные среды разработки —
у каждого свой Linux-юзер, своя PostgreSQL DB, свой HTTPS dev-стенд
`https://dev-<alias>.it-joy.ru`, свой блок портов и свой `.env.development`
закрытый от чтения самим девом. Push-proxy git-зеркало в GitHub через
bot-аккаунт `ssv-bot` (login `ssv555ssv`) → `ssv555/vdole`.

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

Интерактив (full name, выбор веток при merge) — через `~/.claude/scripts/dialog.ps1`
(AskUserQuestion не работает в subagents, dialog.ps1 — universal fallback).

## SSH-конфигурация

Host alias `moscow_my` в `~/.ssh/config` (root@195.2.75.212:53847).

## Bootstrap — однократный, идемпотентный

`lib/bootstrap-server.sh`. Каждый шаг проверяет состояние и skip'ает если уже сделано:

1. Системные юзеры `claude-runner`, `git-mirror` (без shell)
2. Группа `developers` + sshd AllowGroups `developers` в `/etc/ssh/sshd_config.d/01-hardening.conf`
3. **Filesystem isolation ACLs** — `setfacl` блокирует `developers` от `/var`, `/backup`, `/snap`, `/media`, `/mnt`, `/cdrom`, `/opt/{certbot,containerd,dev-skill,qdrant}`; traverse-only на `/home`, `/opt`, `/srv`, `/srv/git`
4. Claude CLI в `/opt/claude/` через `bun install -g`
5. `/opt/claude-shared/` — копия allowlisted скилов, dev-CLAUDE.md, codex.md, DEV_GUIDE.md, memory/
6. Setuid-wrapper `/usr/local/bin/claude` (4755 claude-runner:claude-runner) — компилируется из `setuid-claude-wrapper.c`. Блокирует флаги `--config-dir/--projects-dir/--skills-dir/--hooks-dir/--settings`, очищает env, ставит HOME из passwd
7. Bare repo `/srv/git/VDole.git` (`git init --bare --shared=group --initial-branch=main`) + хуки `pre-receive` (пропускает не-developers) + `post-receive` (queue trigger) + origin = `git@github.com:ssv555/vdole.git`
8. Hooks dir + config + HEAD — `g-w` (девы НЕ могут переписать pre-receive хук)
9. `/home/git-mirror/.ssh/id_ed25519` (фингерпринт `NZ5QUSFA...`) — бэкап ключа из `D:\Data\Backup\Ubuntu-Servers\moscow_my\keys-self\git-mirror\`
10. `mirror-push.sh` + systemd `vdole-mirror.service` + `vdole-mirror.path` (inotify) + sudoers
11. **Daily 06:00 cleanup** — `dev-services-cleanup.sh` + `dev-services-cleanup.timer` убивает все процессы на портах 40001-49999 (защита от забытых `bun run dev`)

Bootstrap триггерится автоматически при первом `/dev add`. Маркер `/opt/dev-skill/.bootstrap-ok`. Можно запустить вручную: `/dev bootstrap`.

## `/dev add <alias> [<repo>]` — полный flow

При указании `<repo>` — полностью авто-настроенная среда. Без `<repo>` — только Linux-юзер.

### ⚠️ Ручная подготовка ПЕРЕД `/dev add <alias>`

Шеф ОБЯЗАН зарегистрировать OAuth redirect URI для нового дев-стенда во всех провайдер-консолях, ИНАЧЕ OAuth-flow у дева упадёт на проверке callback'а:

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
   - `adduser --disabled-password` + `usermod -aG developers` + `usermod -aG <alias> claude-runner`
   - `~/.ssh/authorized_keys` (pub-half from chief)
   - `~/.claude/` (root:claude-runner 750) + симлинки на shared (skills/CLAUDE.md/codex.md/DEV_GUIDE.md/memory)
   - `~/.claude/projects` + `~/.claude/sessions` + `~/.claude/.credentials.json` (claude-runner:claude-runner 700/600 — дев НЕ читает)
   - `~/projects/` (`<alias>:<alias>` 755)
   - git config user.name/user.email
5. **Server (clone + tweak):**
   - `git clone /srv/git/<repo>.git ~/projects/<repo>` (origin = bare local path)
   - `chgrp -R claude-runner` + `chmod g+s` на dirs → claude-runner может писать в дев-проект
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
   - **Perms: 600 claude-runner:claude-runner** — дев НЕ читает прямо из shell. Bun читает только запущенный через claude (setuid → claude-runner).
8. **Server:** `bun install` от имени дева
9. **Chief PC:**
   - `~/.claude/developers/<alias>/info.json` (alias/email/fp/created_at/...)
   - `~/.claude/developers/<alias>/onboarding.md` — текст для пересылки деву
   - Append row в `D:\Data\Backup\Ubuntu-Servers\moscow_my\SSH_KEYS_INVENTORY.md`

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

Защита от забытых `bun run dev` (дев ушёл спать / в отпуск / уволен):

- systemd timer `dev-services-cleanup.timer` (`OnCalendar=*-*-* 06:00:00 Persistent=true`)
- запускает `/opt/dev-skill/dev-services-cleanup.sh` под root
- скрипт находит все процессы listening на 40001-49999 через `ss`, отправляет SIGTERM, ждёт 5s, SIGKILL стойким
- лог в `/var/log/dev-services-cleanup.log`
- **НЕ убивает** SSH сессии, bash, claude — только port-listening dev-серверы

Manual force-cleanup: `sudo systemctl start dev-services-cleanup.service`

## Allowlist скилов

`C:\Users\ssv55\.claude\developers\skills_allowlist.json` — single source of truth.

Sync через `/dev sync-skills` пишет в `/opt/claude-shared/skills/` (root-owned read-only).
Дев'ам отдаются:
- `pre-deploy-check`, `pre-deploy-autotests`
- `version-up`, `session-archive`
- `dev-commit`, `dev-push`, `dev-reset`, `dev-info`

## Раскладка ФС на сервере

```
/opt/claude/                            root:root 755                    ← бинарь claude
/opt/claude-shared/                     root:root 755                    ← общая конфигурация
  skills/                               (allowlist'ом)
  CLAUDE.md                             dev-версия (только code quality + workflow)
  codex.md, DEV_GUIDE.md, memory/
/opt/dev-skill/                         root:root 755                    ← server-side скрипты
  bootstrap-server.sh, add-user.sh, del-user.sh, list-users.sh
  setuid-claude-wrapper.c
  mirror-push.sh, vdole-mirror.{service,path}
  pre-receive.sh, post-receive.sh
  dev-services-cleanup.{sh,service,timer}
  nginx-dev-template.conf
  dev-shared-CLAUDE.md, codex.md, DEV_GUIDE.md, memory/
  .bootstrap-ok

/usr/local/bin/claude                   claude-runner:claude-runner 4755 ← setuid wrapper

/home/<dev>/                            <dev>:<dev>             750       ← НЕ 755, дев приватен
  .ssh/                                 <dev>:<dev> 700
  .claude/                              root:claude-runner 750            ← дев НЕ заходит
    skills    → /opt/claude-shared/skills    (root-symlink)
    CLAUDE.md → /opt/claude-shared/CLAUDE.md
    codex.md, DEV_GUIDE.md, memory       → /opt/claude-shared/...
    projects/                           claude-runner:claude-runner 700   ← claude пишет
    sessions/                           claude-runner:claude-runner 700
    .credentials.json                   claude-runner:claude-runner 600
  projects/                             <dev>:<dev>             755
    <repo>/                             <dev>:claude-runner     2775      ← setgid, claude может писать
      .env.development                  claude-runner:claude-runner 600   ← дев НЕ читает

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
- `/var`, `/backup`, `/lost+found`, `/snap`, `/media`, `/mnt`, `/cdrom` — full block
- `/opt/{certbot,containerd,dev-skill,qdrant}` — full block
- `ls /home`, `ls /opt`, `ls /srv` — traverse-only (только cd по точному пути)
- `/etc/nginx` (750 root:root)
- Чужие процессы в `ps aux` (`hidepid=invisible` на `/proc`)
- Чужие SSH/auth логи (`/var` blocked)
- Свой `~/.claude/` (root:claude-runner — дев НЕ в claude-runner группе)
- `.env.development` (claude-runner:claude-runner 600)

## Что НЕ делать

- Не запускать `/dev add`/`del`/`bootstrap` без явного запроса пользователя
- Не читать `/home/<dev>/.claude/.credentials.json` или содержимое архивов
- Не пушить в protected branches через bot-аккаунт — нарушает audit-trail
- Не редактировать allowlist без подтверждения
- Не показывать содержимое SSH private-key и `.env.development` в чате (секреты)
- Не запускать `bun run dev` от имени дева напрямую — только через claude

## Зависимости (выполнены 2026-05-27)

1. ✅ SSH-порт мигрирован на 53847
2. ✅ GitHub bot-аккаунт `ssv-bot` (login `ssv555ssv`) создан, приглашён в `ssv555/vdole`
3. ✅ Bot SSH-key (FP `NZ5QUSFA`) добавлен в bot's GitHub SSH settings, бэкап на ПК в `keys-self/git-mirror/`
