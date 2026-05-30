---
name: dev-01-status
description: Show current dev state — branch, commits ahead of main, dirty files, last commit. Read-only, no side effects. Use when user says "/dev-01-status", "где я", "статус", "/d01".
model: sonnet
allowed-tools: Bash(*), Read(*)
---

# dev-01-status

«Где я сейчас?» — read-only сводка по текущему состоянию работы.

## Status block

```
SKILL:  dev-01-status
MODEL:  sonnet
```

## Алгоритм

1. **Git-репо проверка:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```

2. **Собрать данные:**
   ```bash
   ALIAS=$(whoami)
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   HEAD_SHA=$(git rev-parse --short HEAD)
   AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo '?')
   BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo '?')
   DIRTY=$(git status --porcelain | wc -l)
   LAST_LOG=$(git log -1 --oneline)
   ```

3. **Проверить тип ветки:**
   - Protected (`main`, `master`, `prod`, `production`, `release/*`) → ❌ WARNING.
   - `dev/<alias>/<slug>` где `<alias>` совпадает с whoami → ✓ correct.
   - `dev/<other>/...` → ⚠ чужая dev-ветка.
   - Другое → ⚠ нестандартное имя.

4. **Audit-log:**
   ```bash
   sudo /usr/local/sbin/dev-audit-log dev-01-status "$BRANCH" "status check"
   ```

5. **Вывести таблицу:**
   ```
   Alias:    <alias>
   Branch:   <branch>           [✓ correct / ❌ protected / ⚠ other-dev]
   HEAD:     <sha> — <last commit subject>
   Ahead of main:   <N> commits
   Behind main:     <M> commits         (если M>0 → совет: `/dev-08-reset`)
   Dirty files:     <K>                  (если K>0 → совет: `/dev-05-commit`)
   ```

6. **Хинты:**
   - `dirty>0` → «Незакоммиченные изменения: запусти `/dev-05-commit` для сохранения».
   - `behind>0` → «main ушёл вперёд: запусти `/dev-08-reset` для rebase».
   - `ahead>0 dirty=0 behind=0` → «Готова к ревью? Запусти `/dev-09-finish`».

## Что НЕ делать

- Не модифицировать ничего — это read-only.
- Не делать `git fetch` без необходимости (медленно, плюс показывает свежесть только origin).
