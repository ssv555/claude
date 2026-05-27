---
name: dev-reset
description: Sync current branch with latest main from origin (fetch + rebase). Refuses if there are uncommitted changes — commit first via /dev-commit. Use when user says "/dev-reset", "подтяни main", "обнови ветку", "ресет на main", "/dr".
model: sonnet
allowed-tools: Bash(*), Read(*)
---

# dev-reset

Подтянуть актуальный `main` из origin и сделать rebase текущей dev-ветки.

## Status block

```
SKILL:  dev-reset
MODEL:  sonnet
```

## Алгоритм

1. **Проверить git-репо:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```

2. **Проверить отсутствие незакоммиченных изменений:**
   ```bash
   git status --porcelain
   ```
   Если есть — ОТКАЗ: «Сначала закоммить через `/dev-commit`, потом запусти `/dev-reset` снова».

3. **Узнать ветку:**
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```

4. **Fetch origin с retry** (3 попытки, backoff 2s→4s→8s, вывод ошибок каждой попытки):
   ```bash
   git fetch origin
   ```

5. **Sync — поведение зависит от ветки:**

   - **Detached HEAD** или ветка = `main`:
     ```bash
     git checkout main
     git reset --hard origin/main
     ```

   - Ветка = `master`/`prod`/`production`/`release/*`:
     ОТКАЗ — не должны быть в этой ветке вообще. Сказать пользователю переключиться на свою dev-ветку.

   - **Ветка `dev/<alias>/*`** (правильная для разработчика):
     ```bash
     git rebase origin/main
     ```
     Если conflict — оставить ребейз in-progress, сказать пользователю разрешить вручную и `git rebase --continue`.

   - **Любая другая ветка** (не protected, не dev/*): запросить подтверждение, что эта ветка — рабочая, и сделать `git rebase origin/main`.

6. **Показать результат:**
   ```bash
   git log -1 --oneline
   git rev-parse --abbrev-ref HEAD
   git status -s
   ```

## Что НЕ делать

- Не делать `git reset --hard` на dev-ветке — это удалит локальную работу.
- Не использовать `--force` ни в каких командах.
- Не игнорировать conflicts — пользователь должен их видеть и решать.
