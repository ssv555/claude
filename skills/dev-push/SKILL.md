---
name: dev-push
description: Stage all + commit + push to origin (bare repo → mirrors to GitHub). Same branch guard as dev-commit. Use when user says "/dev-push", "запушить", "коммит и пуш", "/dp".
model: sonnet
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*)
---

# dev-push

Коммит + push в origin (bare-repo на сервере → mirror в GitHub).

## Status block

```
SKILL:  dev-push
MODEL:  sonnet
```

## Алгоритм

1. **Выполнить весь алгоритм `dev-commit`** (branch guard + commit message + commit).

2. **После успешного коммита — push:**
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   git push -u origin "$BRANCH"
   ```

3. **Retry** при network errors: 3 попытки с exponential backoff (2s → 4s → 8s), выводить ошибку каждой попытки.

4. **Показать результат:**
   - Ветка, hash, commit message.
   - Подтвердить успешный push.
   - Напомнить: «когда задача готова к review — скажи шефу, он запустит `/dev merge <твой-alias>`».

## Что НЕ делать

- Не пушить в `main`/`master`/`prod`/`production`/`release/*` — guard в dev-commit это предотвращает.
- Не использовать `--force` / `--force-with-lease` без явного разрешения шефа.
- Не пушить чужие ветки (`dev/<other-alias>/*`).
