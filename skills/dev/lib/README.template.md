# Welcome, {{ALIAS}}

Твоя изолированная dev-среда на `moscow_my`: свой Linux-юзер, PostgreSQL-БД, HTTPS-стенд, Claude.

---

## Окружение

| Параметр | Значение |
|---|---|
| Linux user | `{{ALIAS}}` |
| HTTPS dev-стенд | https://dev-{{ALIAS}}.it-joy.ru |
| API порт | `{{PORT_API}}` |
| Frontend HMR порт | `{{PORT_HMR}}` |
| TG-bot порт | `{{PORT_BOT_TG}}` |
| MAX-bot порт | `{{PORT_BOT_MAX}}` |
| PostgreSQL DB | `{{DB_NAME}}` |
| PostgreSQL user | `{{DB_USER}}` |
| Repo | `~/projects/{{REPO_NAME}}` |
| `.env.development` | `~/projects/{{REPO_NAME}}/.env.development` ({{ALIAS}}:{{ALIAS}} 600 — ты owner, читаешь свободно; в репо НЕ коммитить) |

---

## Доступ (Termius / любой SSH-клиент)

```
Host:    {{HOST_IP}}
Port:    {{SSH_PORT}}
User:    {{ALIAS}}
```

Private key передан тебе шефом отдельно через защищённый канал (TG / Signal). Импортируй его в Termius (Settings → Keychain → Import), привяжи к этому host'у.

---

## Что внутри

- **Claude Code** установлен глобально (`/usr/local/bin/claude`), запускается как ты сам (без setuid wrapper'а — UID = твой)
- **RULES** (`/opt/claude-shared/RULES.md`) — обязательное принятие при первом интерактивном логине (gate показывает текст → ты вводишь `YES, I AGREE`). При апдейте правил шефом — принимаешь заново.
- **Skills** разделяемые, read-only — общие для всех девов на сервере. Доступные тебе:
  - Workflow: `/dev-00-start` (старт задачи + уведомление шефа), `/dev-01-status` (где я), `/dev-05-commit`, `/dev-07-commit-push`, `/dev-08-reset`, `/dev-09-finish` (финал + уведомление шефа)
  - Справка / аудит: `/dev-info`
  - Качество: `/pre-deploy-check-build`, `/pre-deploy-autotests`, `/version-up`, `/session-archive`
- **CLAUDE.md / codex.md / DEV_GUIDE.md** — read-only, симлинки на shared. Запусти `claude` и попроси `прочитай CLAUDE.md` для общего онбординга по коду
- **Memory** (`~/.claude/memory/`) — твоя личная, изолированная от других девов. Claude пишет туда сам по мере работы
- **Sessions / projects** (`~/.claude/sessions/`, `~/.claude/projects/`) — твоя приватная история сессий

---

## Проверка канала (Claude → Amsterdam)

Весь трафик к Anthropic/Cloudflare/Google/etc уходит через amsterdam_my (wg0). Проверь:

```bash
curl -sS --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep -E "^(ip|colo|loc)="
curl -sS --max-time 5 -o /dev/null -w "anthropic remote_ip=%{remote_ip} http=%{http_code}\n" https://api.anthropic.com/
```

Должно: `ip=77.238.231.203`, `colo=AMS`, `loc=NL`, `anthropic remote_ip=160.79.x.x http=404`.
Если colo=DME / loc=RU — маршруты съехали, скажи шефу.

---

## Первые шаги

1. Зайди по SSH через Termius.
2. Запусти Claude:
   ```bash
   claude
   ```
3. Внутри Claude — открой проект и стартуй dev:
   ```bash
   cd ~/projects/{{REPO_NAME}}
   bun run dev
   ```
4. Открой https://dev-{{ALIAS}}.it-joy.ru — должен подняться фронт.

---

## Передача файлов и конфиденциальность

- **SFTP / WinSCP / scp заблокированы** для группы `developers` на уровне sshd
  (`ForceCommand /bin/bash` в `/etc/ssh/sshd_config.d/02-developers-no-sftp.conf`).
  Подключение SFTP-клиентом сразу упадёт на согласовании протокола.
- **Передача кода через `git push`** — это легитимный канал. Твоя ветка пушится
  в bare repo на сервере, оттуда зеркалится в GitHub. Шеф видит всё.
- **Шеф ↔ дев обмен файлами** — через `git`, или через Telegram, или через clipboard
  в terminal (`base64 < file`). SFTP не нужен.
- **Audit-log SFTP** включён на сервере (`Subsystem sftp ... -l INFO -f AUTH`) — даже если
  твою группу когда-то поменяют, любые SFTP-сессии будут залогированы в `journalctl -u ssh`.
- **Код проекта — собственность шефа.** Локальная копия для работы — норма (git clone
  + работа через claude). Распространение кода вне проекта — нарушение NDA.

---

## Что НЕЛЬЗЯ

- **Коммитить секреты** (`.env*`, ключи, токены) — даже свой `.env.development`. Pre-receive хук имеет best-effort защиту, но это не лицензия — если попало, СТОП и зови шефа.
- **Пушить в `main`, `master`, `release/*`, `prod`, `production`** — заблокировано серверным pre-receive хуком. Твоя ветка — `dev/{{ALIAS}}/<slug>`, создаётся автоматом через `/dev-00-start` или `/dev-05-commit`.
- **Менять файлы вне `~/projects/{{REPO_NAME}}`** — у тебя нет прав на shared (`/opt/`), nginx (`/etc/nginx/`), bare repo (`/srv/git/`), чужие home (`/home/*`).
- **Смешивать задачи в одной ветке/пуше** — Rule 1 из RULES.md. Новый таск = новый `/dev-00-start`.

---

## Git workflow

Origin указывает на локальный bare repo `/srv/git/VDole.git`. При push:
- Хук `pre-receive` проверяет ветку (защищённые ветки отказывают)
- Хук `post-receive` триггерит mirror-push → твой коммит автоматически зеркалится в GitHub `ssv555/vdole`

Команды-обёртки (используй их вместо ручных `git`):
- `/dev-00-start` — старт задачи: pull main + новая ветка `dev/{{ALIAS}}/<slug>`
- `/dev-01-status` — где я сейчас (ветка, commits, dirty files)
- `/dev-05-commit` — staged + commit с авто-сообщением (один таск = один коммит)
- `/dev-07-commit-push` — то же + push (один таск = один push)
- `/dev-08-reset` — `git fetch origin && git rebase origin/main`
- `/dev-09-finish` — финал задачи: pre-deploy-check-build + autotests + push + уведомление шефа в TG
- `/dev-info` — справка по командам

---

## Daily cleanup

Каждые сутки в 06:00 МСК systemd-timer убивает висящие процессы на dev-портах (40001-49999) — защита от забытого `bun run dev`. SSH-сессии, bash, `claude` НЕ трогает.

---

## Кому жаловаться

Шеф: ssv (Telegram). По всему — багам, инфре, кредам реальных интеграций (OAuth client_secret, SMS, Email — выдаёт штучно по запросу).
