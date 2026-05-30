# Welcome, {{ALIAS}}

Это твоя dev-среда на личном сервере `moscow_my`. Полностью изолирована — свой Linux-юзер, своя PostgreSQL-БД, свой HTTPS-стенд, свой Claude.

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
| `.env.development` | `~/projects/{{REPO_NAME}}/.env.development` (claude-runner:claude-runner 600 — ты НЕ читаешь напрямую, только через `claude`) |

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

- **Claude Code** установлен глобально, запускается командой `claude` (через setuid-wrapper — стартует как `claude-runner`, читает `.env.development`)
- **Skills** разделяемые, read-only — общие для всех девов на сервере. Доступны: `/dev-info`, `/dev-commit`, `/dev-push`, `/dev-reset`, `/version-up`, `/session-archive`, `/pre-deploy-check`, `/pre-deploy-autotests`
- **CLAUDE.md / codex.md / DEV_GUIDE.md** — read-only, симлинки на shared. Запусти `claude` и попроси `прочитай CLAUDE.md` для общего онбординга по коду
- **Memory** (`~/.claude/memory/`) — твоя личная, изолированная от других девов. Claude пишет туда сам по мере работы
- **Sessions / projects** (`~/.claude/sessions/`, `~/.claude/projects/`) — твоя приватная история сессий

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

## Что НЕЛЬЗЯ

- **Читать `.env.development` напрямую из shell** (`cat`, `less`, `vim`) — упадёт `Permission denied`. Это норма: креды читает только `bun` запущенный через `claude`. Если деву реально нужно посмотреть значение — попроси `claude` показать (он отрендерит безопасно).
- **Пушить в `main`, `master`, `release/*`, `prod`, `production`** — заблокировано серверным pre-receive хуком. Делай свою ветку `{{ALIAS}}/feature-name`, шеф мерджит через `/dev-merge {{ALIAS}}`.
- **Менять файлы вне `~/projects/{{REPO_NAME}}`** — у тебя нет прав на shared (`/opt/`), nginx (`/etc/nginx/`), bare repo (`/srv/git/`), чужие home (`/home/*`).
- **Запускать `bun run dev` напрямую как `{{ALIAS}}`** — `.env.development` недоступен. Только через `claude`.

---

## Git workflow

Origin указывает на локальный bare repo `/srv/git/VDole.git`. При push:
- Хук `pre-receive` проверяет ветку (защищённые ветки отказывают)
- Хук `post-receive` триггерит mirror-push → твой коммит автоматически зеркалится в GitHub `ssv555/vdole`

Команды-обёртки (используй их вместо ручных `git`):
- `/dev-commit` — staged + commit с авто-сообщением
- `/dev-push` — staged + commit + push
- `/dev-reset` — `git fetch origin && git rebase origin/main`
- `/dev-info` — справка по командам

---

## Daily cleanup

Каждые сутки в 06:00 МСК systemd-timer убивает все висящие процессы на dev-портах (40001-49999) — защита от забытого `bun run dev`. SSH-сессии, bash, `claude` НЕ трогает.

---

## Кому жаловаться

Шеф: ssv (Telegram). По всему — багам, инфре, кредам реальных интеграций (OAuth client_secret, SMS, Email — выдаёт штучно по запросу).
