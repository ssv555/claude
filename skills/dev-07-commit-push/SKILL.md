---
name: dev-07-commit-push
description: Stage all + commit + push to origin (bare repo → mirrors to GitHub). Same branch guard as dev-05-commit. ONE task per push — refuses to push if the branch contains commits for multiple unrelated tasks. Use when user says "/dev-07-commit-push", "запушить", "коммит и пуш", "/d07".
model: sonnet
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*)
---

# dev-07-commit-push

Коммит + push в origin (bare-repo на сервере → mirror в GitHub).

**Правило одного таска:** в `git push` уходят коммиты одной задачи. Смешивать задачи в одном push'е **запрещено** — это нарушает Rule 1 из `/opt/claude-shared/RULES.md`.

## Status block

```
SKILL:  dev-07-commit-push
MODEL:  sonnet
```

## Алгоритм

1. **Выполнить полный алгоритм `dev-05-commit`** (branch guard + one-task check + commit message + commit).

2. **Pre-push «один таск» sanity-check:**
   - Получить коммиты, которые сейчас уйдут на сервер:
     ```bash
     BRANCH=$(git rev-parse --abbrev-ref HEAD)
     COMMITS_TO_PUSH=$(git log --oneline origin/main..HEAD 2>/dev/null || git log --oneline HEAD)
     ```
   - Если коммитов >1 — посмотреть на их subjects. Если разные префиксы (`feat:` + `fix:` + `refactor:` всё разом по совсем разному скоупу), или явно про разные фичи — спросить пользователя:
     > «На пуш уходит N коммитов:
     > - <commit1 subject>
     > - <commit2 subject>
     > - ...
     >
     > Они про одну задачу или это несколько? Если несколько — нужно разделить на отдельные ветки/пуши.
     > 1. Да, одна задача — продолжаем push.
     > 2. Нет, разные — отменить push, перенесу лишние коммиты в новые ветки.»
   - На «1» — push. На «2» — отменить и подсказать `git cherry-pick`/`git reset --soft` маршрут (без авто-действий — пусть пользователь сам разрулит).

3. **Push с retry** (3 попытки, backoff 2s/4s/8s, выводить ошибку каждой попытки):
   ```bash
   git push -u origin "$BRANCH"
   ```

4. **Audit-log:**
   ```bash
   HEAD_SHA=$(git rev-parse --short HEAD)
   COMMITS_COUNT=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 1)
   sudo /usr/local/sbin/dev-audit-log dev-07-commit-push "$BRANCH" "$HEAD_SHA pushed $COMMITS_COUNT commits"
   ```

5. **Результат:**
   - Ветка, sha, последний commit message.
   - Напомнить: «Когда задача готова к review — `/dev-09-finish` (запустит проверки и уведомит шефа).»

## Что НЕ делать

- Не пушить в `main`/`master`/`prod`/`production`/`release/*` — guard в dev-05-commit это предотвращает.
- Не использовать `--force` / `--force-with-lease` без явного разрешения шефа.
- Не пушить чужие ветки (`dev/<other-alias>/*`).
- Не смешивать задачи в одном пуше — Rule 1 RULES.md.
