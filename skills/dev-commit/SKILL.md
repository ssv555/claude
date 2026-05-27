---
name: dev-commit
description: Stage all + commit with a branch guard. If on a protected branch (main/master/prod/production/release/*) or detached HEAD — automatically creates dev/<alias>/<auto-slug> and switches to it. AI writes the commit message. Use when user says "/dev-commit", "коммит", "закоммить", "/dc".
model: sonnet
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*)
---

# dev-commit

Безопасный коммит для разработчика на `moscow_my`. Никогда не коммитит в `main`/`master`/`prod`/`production`/`release/*` — сначала переключается на свою ветку.

## Status block

```
SKILL:  dev-commit
MODEL:  sonnet
```

## Алгоритм

1. **Проверить, что мы в git-репо:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```
   Если нет — отказать и сказать пользователю запустить из корня репозитория.

2. **Узнать alias:** `ALIAS=$(whoami)`.

3. **Определить текущую ветку:**
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```
   - Если `HEAD` (detached) ИЛИ `BRANCH` в списке `main master prod production` ИЛИ матчится `release/*` →
     запросить у пользователя короткое описание задачи (1–3 слова, на английском).
     Создать новую ветку: `git checkout -b "dev/${ALIAS}/${slug}"`, где `slug` — kebab-case описания.
   - Иначе — продолжить на текущей ветке.

4. **Проверить, что есть что коммитить:**
   ```bash
   git status --porcelain
   ```
   Если пусто — сказать «нечего коммитить» и выйти.

5. **Показать пользователю краткий обзор изменений:**
   ```bash
   git status -s
   git diff --stat
   ```

6. **Сгенерировать commit message:**
   - Прочитать `git diff --cached` и `git diff` для понимания сути.
   - Формат: одна строка ≤72 символов, present-tense, императив, English.
   - Префиксы по типу: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
   - Например: `feat: add email validation to signup form`.

7. **Закоммитить:**
   ```bash
   git add -A
   git commit -m "<message>"
   ```

8. **Показать результат:**
   ```bash
   git log -1 --oneline
   git rev-parse --abbrev-ref HEAD
   ```
   Сообщить пользователю: ветка, хэш, сообщение.

## Запрещено

- Никогда не коммитить в protected-ветки (server pre-receive hook всё равно отклонит push, но мы не доводим до этого).
- Не амендить чужие коммиты.
- Не использовать `--no-verify` без явного разрешения шефа.
