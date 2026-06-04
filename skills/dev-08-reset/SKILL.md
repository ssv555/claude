---
name: dev-08-reset
description: Sync current branch with latest origin main (fetch + rebase); refuses on uncommitted changes. Use when user says "/dev-08-reset", "подтяни main", "обнови ветку", "ресет на main".
model: sonnet
allowed-tools: Bash(*), Read(*)
---

# dev-08-reset

Подтянуть актуальный `main` из origin и сделать rebase текущей dev-ветки.

## Status block

```
SKILL:  dev-08-reset
MODEL:  sonnet
```

## Алгоритм

1. **Git-репо проверка:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```

2. **Чистота WC:**
   ```bash
   git status --porcelain
   ```
   Не пусто — ОТКАЗ: «Сначала закоммить через `/dev-05-commit`, потом запусти `/dev-08-reset` снова».

3. **Узнать ветку:**
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```

4. **Fetch с retry** (3 попытки, backoff 2s/4s/8s, выводить ошибки):
   ```bash
   git fetch origin
   ```

5. **Sync — по ветке:**
   - **Detached HEAD** или `main`:
     ```bash
     git checkout main
     git reset --hard origin/main
     ```
   - `master`/`prod`/`production`/`release/*`: ОТКАЗ — не должен в protected. Сказать пользователю переключиться на свою dev-ветку.
   - **`dev/<alias>/*`**:
     ```bash
     git rebase origin/main
     ```
     Conflict — оставить in-progress, попросить разрешить вручную и `git rebase --continue`.
   - Другая нестандартная ветка: запросить подтверждение, потом `git rebase origin/main`.

6. **Audit-log:**
   ```bash
   HEAD_SHA=$(git rev-parse --short HEAD)
   sudo /usr/local/sbin/dev-audit-log dev-08-reset "$BRANCH" "rebased onto origin/main, head=$HEAD_SHA"
   ```

7. **Результат:**
   ```bash
   git log -1 --oneline
   git rev-parse --abbrev-ref HEAD
   git status -s
   ```

## Что НЕ делать

- Не делать `git reset --hard` на dev-ветке — удалит локальную работу.
- Не использовать `--force` ни в чём.
- Не игнорировать conflicts — пользователь должен видеть и решать.
