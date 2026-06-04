---
name: dev-09-finish
description: Finish a task — run checks + autotests, final commit + push, notify chief (audit log + TG webhook with branch/sha/diff). Use when user says "/dev-09-finish", "закончил задачу", "готово, зови шефа".
model: sonnet
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*), Skill(*)
---

# dev-09-finish

Финализация задачи. Прогоняет проверки, делает финальный push, уведомляет шефа.

## Status block

```
SKILL:  dev-09-finish
MODEL:  sonnet
```

## Алгоритм

1. **Git-репо + alias:**
   ```bash
   git rev-parse --is-inside-work-tree
   ALIAS=$(whoami)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```

2. **Branch guard:**
   - Если `BRANCH` не матчит `dev/<alias>/*` — ОТКАЗ: «Ты на ветке `$BRANCH`. `/dev-09-finish` работает только с твоими dev-ветками. Переключись или используй `/dev-00-start`».

3. **One-task confirmation:**
   - Показать все коммиты на ветке относительно main:
     ```bash
     git log --oneline origin/main..HEAD
     ```
   - Спросить пользователя: «Это всё про одну задачу?
     1. Да — финализируем.
     2. Нет — отмена; разнеси по отдельным веткам.»

4. **Чистота WC:**
   - Если есть uncommitted → запустить `/dev-05-commit` (skill chain) → дождаться.

5. **Pre-deploy check** (typecheck/lint/build) — через скил:
   ```
   /pre-deploy-check-build
   ```
   Падает → СТОП. Показать ошибки, отказаться завершать. Сказать: «Исправь и запусти `/dev-09-finish` заново».

6. **Pre-deploy autotests** — через скил:
   ```
   /pre-deploy-autotests
   ```
   Падает → СТОП аналогично.

7. **Final push** (даже если коммитов после последнего push не было — для надёжности):
   ```bash
   git push -u origin "$BRANCH"
   ```
   Retry 3x с backoff.

8. **Собрать метаданные для уведомления:**
   ```bash
   HEAD_SHA=$(git rev-parse HEAD)
   COMMITS=$(git rev-list --count origin/main..HEAD)
   STATS=$(git diff --shortstat origin/main..HEAD)
   ADDED=$(echo "$STATS"   | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
   REMOVED=$(echo "$STATS" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' || echo 0)
   LAST_SUBJECT=$(git log -1 --format='%s')
   ```

9. **Notify chief** через привилегированный хелпер:
   ```bash
   sudo /usr/local/sbin/dev-notify-finish "$BRANCH" "$HEAD_SHA" "$COMMITS" "$ADDED" "$REMOVED" "$LAST_SUBJECT"
   ```
   Хелпер всегда пишет в `/opt/claude-shared/audit/finished_branches.log` + опционально POST на webhook шефа (TG).

10. **Audit-log:**
    ```bash
    sudo /usr/local/sbin/dev-audit-log dev-09-finish "$BRANCH" "FINISHED head=$HEAD_SHA commits=$COMMITS +$ADDED/-$REMOVED"
    ```

11. **Сказать пользователю:**
    > ✓ Задача финализирована.
    > Ветка: `dev/<alias>/<slug>`, HEAD: `<sha>`, коммитов: N, diff: +X/-Y.
    > Шеф уведомлён. Дальше он запустит `/dev-merge <твой-alias>` на своём PC.
    > Можешь начинать новую задачу через `/dev-00-start`.

## Что НЕ делать

- Не пропускать pre-deploy-check-build / pre-deploy-autotests «потому что я уже запускал». Они тут официальный signoff.
- Не пушить с `--force` если push failed после rebase. Если конфликт — это новая работа, она требует `/dev-08-reset` и нового цикла.
- Не вызывать `/dev-merge` сам — это chief-only скил.
- Не финализировать ветку с несколькими задачами — Rule 1.
