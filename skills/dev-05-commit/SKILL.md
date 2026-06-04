---
name: dev-05-commit
description: Stage all + commit with a branch guard (auto-switches off protected branches to dev/<alias>/<slug>). One task per commit. Use when user says "/dev-05-commit", "коммит", "закоммить".
model: sonnet
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*)
---

# dev-05-commit

Безопасный коммит для разработчика на `moscow_my`. Никогда не коммитит в `main`/`master`/`prod`/`production`/`release/*` — сначала переключается на свою ветку.

**Правило одного таска:** один коммит = одно изменение по одной задаче. Если diff содержит изменения по нескольким независимым задачам — НЕ коммитить всё разом; вернуть пользователю и предложить разделить.

## Status block

```
SKILL:  dev-05-commit
MODEL:  sonnet
```

## Алгоритм

1. **Git-репо проверка:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```

2. **Узнать alias:** `ALIAS=$(whoami)`.

3. **Определить текущую ветку:**
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```
   - `HEAD` (detached) ИЛИ `BRANCH` в `main master prod production` ИЛИ матчит `release/*` →
     запросить короткое описание (1-3 слова, English) → `git checkout -b "dev/${ALIAS}/${slug}"`.
   - Иначе — продолжить.

4. **Что коммитить:**
   ```bash
   git status --porcelain
   ```
   Пусто — «нечего коммитить», выход.

5. **Show overview:**
   ```bash
   git status -s
   git diff --stat
   ```

6. **Заглянуть в diff** (`git diff --cached` и `git diff`):
   - **Sanity check «один таск»:** если изменения затрагивают явно разные подсистемы / фичи / слои без видимой связи (например: правка auth + правка UI компонента не связанного с auth + миграция БД для третьей фичи) — ОСТАНОВИТЬСЯ. Сообщить пользователю:
     > «Diff выглядит как несколько независимых задач. Правило: один коммит = одна задача. Можешь:
     > 1. Разделить — закоммить только файлы по одной задаче (`git add <files>`, потом `/dev-05-commit` ещё раз для остатка в новой ветке через `/dev-00-start`).
     > 2. Подтвердить что это одна логическая задача — тогда продолжим.»
     - На «продолжить» — закоммитить как есть.
     - На «разделить» — выйти, дождаться пока пользователь сделает `git add` нужных файлов.

7. **Сгенерировать commit message:**
   - Формат: одна строка ≤72 символов, present-tense императив, English.
   - Префиксы: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
   - Пример: `feat: add email validation to signup form`.

8. **Закоммитить:**
   ```bash
   git add -A
   git commit -m "<message>"
   ```

9. **Audit-log:**
   ```bash
   COMMIT_SHA=$(git rev-parse --short HEAD)
   sudo /usr/local/sbin/dev-audit-log dev-05-commit "$BRANCH" "$COMMIT_SHA $message"
   ```

10. **Результат:** ветка, sha, message.

## Запрещено

- Коммит в protected-ветки (server pre-receive отклонит, но guard в скиле предотвращает попытку).
- Амендить чужие коммиты.
- `--no-verify` без явного разрешения шефа.
- Смешивать несколько задач в один коммит без подтверждения пользователя.
