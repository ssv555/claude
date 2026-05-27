# Developer Guide — moscow_my

Краткая инструкция для разработчика. Лежит в `/opt/claude-shared/DEV_GUIDE.md`
(read-only). Из bash: `cat /opt/claude-shared/DEV_GUIDE.md`. Из claude:
`/dev-info` или `cat ~/.claude/DEV_GUIDE.md` (симлинк работает только в claude
CLI — твой shell-юзер не имеет доступа к `~/.claude/`).

---

## Окружение

- Сервер: `moscow_my`
- Юзер: твой alias (Linux account)
- Claude Code: уже установлен, общий бинарь `/usr/local/bin/claude` (setuid wrapper)
- Скилы / правила / память: shared, read-only (через симлинки в `~/.claude/`)
- Твоя рабочая папка: `~/projects/` (твой полный доступ)
- Сессии и проекты Claude: `~/.claude/projects/`, `~/.claude/sessions/` (Claude пишет, ты только читаешь)

---

## Доступные скилы (slash-команды)

### Работа с кодом

| Команда | Описание |
|---|---|
| `/dev-info` | Эта инструкция |
| `/dev-commit` | Коммит с проверкой ветки. Если ты на `main`/protected — авто-создаст `dev/<alias>/<slug>` и переключит. AI пишет commit message. |
| `/dev-push` | Коммит + push в origin (bare-repo → mirror в GitHub). |
| `/dev-reset` | `fetch origin` + `rebase` твоей ветки на `main`. Откажет если есть uncommitted — сначала `/dev-commit`. |
| `/pre-deploy-check` | typecheck/lint/build перед сдачей задачи. |
| `/pre-deploy-autotests` | Прогон unit/integration/e2e тестов. |
| `/version-up` | Бамп `APP_VERSION` в проекте. |
| `/session-archive` | Архивирование текущей сессии в `docs/archive/sessions/`. |

### Встроенные в Claude (всегда работают)

`/init`, `/review`, `/code-review`, `/security-review`, `/simplify`, `/skills`,
`/context-show` — стандартные скилы Claude Code.

---

## Workflow задачи

```
1. Получил задачу от шефа
2. /dev-reset           — подтянуть свежий main
3. Делаешь работу       — Claude помогает
4. /dev-push            — коммит + push (в твою ветку dev/<alias>/<slug>)
5. /pre-deploy-check    — typecheck/lint/build
6. /pre-deploy-autotests — тесты
7. Если всё зелёное — пишешь шефу: «готово, ветка dev/<alias>/<slug>»
8. Шеф у себя запустит /dev-merge <твой-alias> — review + merge в main
```

## Запуск dev-сервера — ТОЛЬКО через claude

`.env.development` лежит с правами `600 claude-runner:claude-runner` — твой shell-юзер
НЕ может его читать. Это намеренно: там DB-креды, JWT, OAuth secrets.

Поэтому `bun run dev` из твоего bash **не запустится** (bun не сможет прочесть env).

Правильно: запускай через claude CLI — тогда bun унаследует от claude-runner права
на чтение .env:

```
$ claude
> запусти bun run dev
```

или одной строкой:
```
$ claude -p "запусти bun run dev"
```

Твой dev-стенд после старта будет доступен по https://dev-<твой-alias>.it-joy.ru

---

## Ветки — НИКОГДА не работать в `main`

Защита:

- `pre-receive` хук на bare-repo **физически блокирует** push в `main`, `master`, `prod`, `production`, `release/*`.
- `/dev-commit` и `/dev-push` **отказываются** коммитить в protected-ветки и сами переключают на `dev/<alias>/<slug>`.

Формат твоих веток: `dev/<твой-alias>/<short-slug>`. Пример: `dev/danya/add-otp-field`.

После merge'а шефом твоя ветка **удаляется на сервере**. У тебя локально остаётся — почисти после `/dev-reset` или вручную `git branch -D dev/danya/add-otp-field`.

---

## Что НЕ делать

- Не пушить в protected-ветки (бесполезно — сервер откажет).
- Не использовать `--force` ни в каких git-командах.
- Не править файлы в `~/.claude/skills/`, `~/.claude/CLAUDE.md`, `/opt/claude-shared/` — это root-owned shared, ты не сможешь.
- Не запускать скилы которые не описаны выше — особенно если что-то намекает на «deploy», «prod», «changelog» — это **только шеф**.
- Не коммитить секреты (.env, ключи, токены).
- Не делать `git config --global user.email` — он уже прописан корректно.

---

## Что делать если…

| Ситуация | Решение |
|---|---|
| `/dev-push` падает с network error | retry уже встроен (3 попытки) — если всё равно падает, скажи шефу |
| `/dev-reset` показывает conflict | разреши вручную, `git add` файлы, `git rebase --continue`, потом снова `/dev-reset` |
| Случайно закоммитил секрет | НЕ пушь, скажи шефу немедленно |
| Не понимаю что хочет шеф | Спроси прямо — лучше уточнить, чем сделать не то |
| Тесты падают на чужом коде | Скажи шефу, не «исправляй» чужое самовольно |

---

## Связь

Все вопросы — шефу напрямую (TG/Signal).
