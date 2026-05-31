# Developer Guide — moscow_my

Инструкция для разработчика в `/opt/claude-shared/DEV_GUIDE.md` (read-only). Из bash: `cat /opt/claude-shared/DEV_GUIDE.md`. Из claude: `/dev-info` или `cat ~/.claude/DEV_GUIDE.md` (симлинк работает только из claude CLI).

---

## Окружение

- Сервер: `moscow_my`
- Юзер: твой alias (Linux account)
- Claude Code: `/usr/local/bin/claude` (общий бинарь, бежит как ты)
- Скилы и правила (`skills/`, `CLAUDE.md`, `codex.md`, `DEV_GUIDE.md`, `RULES.md`): shared, read-only через симлинки на `/opt/claude-shared/`
- Память Claude (`~/.claude/memory/`): per-dev, writable
- Твоя рабочая папка: `~/projects/<repo>/`
- Onboarding: `~/README.md` (твои порты, БД, URL)
- NDA / конфиденциальность: `~/AGREEMENT.md` (legal)
- Технические правила: `/opt/claude-shared/RULES.md` (обязательное принятие при логине)

---

## RULES — обязательное принятие при входе

При первом интерактивном логине ты увидишь страницу с правилами и вопрос «type `YES, I AGREE` to accept». До принятия — shell тебя выкинет.

- Хеш SHA-256 правил привязан к версии файла.
- Шеф обновил RULES.md → старый flag протухает → при следующем логине принимаешь заново.
- Принятие пишется в audit-log с твоим alias, IP, временем и хешем.

Если правила больше одного экрана — `Space`/`PgDn` пагинатор, `q` — выход из less. Прочитал → введи `YES, I AGREE` точно как написано.

**Ключевое правило (Rule 1):** один `git push` = один таск. Никогда не мешать две задачи в одном push'е.

---

## Доступные скилы (slash-команды)

### Дневной workflow (рекомендованный порядок)

| # | Skill | Описание |
|---|---|---|
| 00 | `/dev-00-start` | Старт задачи: pull main + `git checkout -b dev/<alias>/<slug>` |
| 01 | `/dev-01-status` | Где я сейчас: ветка, коммиты, dirty files |
| 05 | `/dev-05-commit` | Коммит (с branch guard). Один таск = один коммит |
| 07 | `/dev-07-commit-push` | Коммит + push. Один таск = один push |
| 08 | `/dev-08-reset` | Подтянуть свежий main и отрибейзить твою ветку |
| 09 | `/dev-09-finish` | Финал: pre-deploy-check + autotests + push + уведомление шефа |

Сокращения: `/d00 /d01 /d05 /d07 /d08 /d09`.

### Информация и проверки

| Команда | Описание |
|---|---|
| `/dev-info` | Эта инструкция |
| `/pre-deploy-check` | typecheck/lint/build перед сдачей задачи |
| `/pre-deploy-autotests` | Прогон unit/integration/e2e тестов |
| `/version-up` | Бамп `APP_VERSION` в проекте |
| `/session-archive` | Архив текущей сессии в `docs/archive/sessions/` |

### Встроенные в Claude (всегда работают)

`/init`, `/review`, `/code-review`, `/security-review`, `/simplify`, `/skills`,
`/context-show` — стандартные скилы Claude Code.

---

## Стандартный рабочий день

```
1.  /dev-00-start             ← утро. Подтянуть main + создать ветку
2.  работа + Claude помогает
3.  /dev-05-commit            ← по ходу, после каждого осмысленного шага
4.  /dev-05-commit            ← коммитов может быть много, ПОКА все про ОДНУ задачу
5.  /dev-07-commit-push       ← как только хочешь засинхрить с сервером
6.  работа продолжается
7.  /dev-08-reset             ← если main ушёл вперёд (опционально)
8.  /dev-09-finish            ← задача готова → checks + push + уведомление шефа
```

Шеф у себя запустит `/dev-merge <твой-alias>` — review + merge в main. После
мерджа твоя ветка удаляется с сервера, локально остаётся — почистишь сам.

### Несколько задач за день — несколько циклов 00→09

```
утро:    /dev-00-start  → ...работа task A... → /dev-09-finish
позже:   /dev-00-start  → ...работа task B... → /dev-09-finish
вечером: /dev-00-start  → ...работа task C... → /dev-09-finish
```

НЕ смешивать A+B+C в одной ветке/пуше. Это нарушение Rule 1 RULES.md.

---

## Проверка канала Claude → Anthropic

Claude ходит во внешний мир ТОЛЬКО через Amsterdam (`wg0` туннель), не напрямую с moscow IP:

```bash
# 1. Exit IP и Cloudflare datacenter — должно быть AMS / NL
curl -sS --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep -E "^(ip|colo|loc)="

# 2. Реальный adres api.anthropic.com (должен быть из 160.79.96.0/20)
curl -sS --max-time 5 -o /dev/null -w "anthropic remote_ip=%{remote_ip} http=%{http_code}\n" https://api.anthropic.com/
```

Ожидаемо:
- `ip=77.238.231.203` (amsterdam_my)
- `colo=AMS`, `loc=NL`
- `anthropic remote_ip=160.79.x.x http=404`

Если видишь `colo=DME`/`loc=RU` или IP вне `160.79.96.0/20` — **СТОП**, скажи шефу,
маршруты съехали (вероятно Anthropic поменяли CIDR, надо обновить wg0 на сервере).

---

## Запуск dev-сервера

`.env.development` (`600 <alias>:<alias>`) — ты МОЖЕШЬ его читать (claude/bun бегут как ты), но НЕ коммить — секреты.

```bash
cd ~/projects/<repo>
bun run dev
```

Стенд после старта: `https://dev-<alias>.it-joy.ru`. Забытый bun в фоне прибьёт daily cleanup в 06:00 MSK (порты 40001-49999) — это нормально.

---

## Ветки — НИКОГДА не работать в `main`

Защита:
- `pre-receive` хук на bare-repo **физически блокирует** push в `main`, `master`, `prod`, `production`, `release/*`
- `/dev-05-commit` и `/dev-07-commit-push` **отказываются** коммитить в protected и сами переключают на `dev/<alias>/<slug>`

Формат веток: `dev/<твой-alias>/<short-slug>`. Пример: `dev/danya/add-otp-field`.

После merge'а шефом ветка удаляется на сервере; локально остаётся — почисти `git branch -D dev/danya/add-otp-field`.

---

## Что НЕ делать

См. `/opt/claude-shared/RULES.md` (10 пунктов). Кратко:

- Не пушить в protected-ветки (бесполезно — сервер откажет)
- Не использовать `--force` / `--no-verify` без явного разрешения шефа
- Не редактировать `/opt/claude-shared/*`, `/opt/dev-skill/*` (read-only)
- Не коммитить секреты (.env, ключи, токены)
- Не делать `git config --global user.email` — уже прописан корректно
- Не смешивать задачи в одной ветке/пуше — Rule 1
- Не обходить SFTP-блок — не легитимный канал передачи кода

---

## Что делать если…

| Ситуация | Решение |
|---|---|
| `/dev-07-commit-push` падает с network error | retry уже встроен (3 попытки) — если всё равно падает, скажи шефу |
| `/dev-08-reset` показывает conflict | разреши вручную, `git add` файлы, `git rebase --continue`, потом снова `/dev-08-reset` |
| Случайно закоммитил секрет | НЕ пушь, скажи шефу немедленно |
| `/dev-09-finish` упал на pre-deploy-check | посмотри ошибки, исправь, запусти `/dev-09-finish` снова |
| Заметил баг в чужом коде по ходу задачи | НЕ исправляй здесь. Закончи свою задачу через `/dev-09-finish`, потом `/dev-00-start` новый slug под этот баг |
| Не понимаю что хочет шеф | Спроси прямо — лучше уточнить, чем сделать не то |
| Тесты падают на чужом коде | Скажи шефу, не «исправляй» чужое самовольно |
| После `claude` чёрный экран в Termius | Проверь `echo $TERM` — должно быть `xterm-256color`. В `~/.bashrc` уже стоит, но Termius может перезаписывать через свой профиль |
| Видишь «rules NOT ACCEPTED» в motd | Выйди (`exit`) и зайди по SSH заново — gate покажет правила |

---

## Связь

Все вопросы — шефу напрямую (TG/Signal).
