---
name: dev-00-start
description: Start of a new task — sync main + create a fresh dev branch. Refuses if working copy is dirty. Asks for a short kebab-case slug, then runs git fetch + checkout main + pull --rebase + checkout -b dev/<alias>/<slug>. Use when user says "/dev-00-start", "начать задачу", "новая ветка", "/d00".
model: sonnet
allowed-tools: Bash(*), Read(*)
---

# dev-00-start

Старт новой задачи. Подтягивает свежий `main` и создаёт твою dev-ветку.

## Status block

```
SKILL:  dev-00-start
MODEL:  sonnet
```

## Алгоритм

1. **Git-репо проверка:**
   ```bash
   git rev-parse --is-inside-work-tree
   ```
   Нет — отказ.

2. **Узнать alias:** `ALIAS=$(whoami)`.

3. **Чистота WC:**
   ```bash
   git status --porcelain
   ```
   Если не пусто — ОТКАЗ: «Сначала закоммить через `/dev-05-commit` или откати; `/dev-00-start` стартует с чистого листа».

4. **Запросить слаг задачи.**
   - Через `dialog.ps1` или интерактивно в чате: «Короткий kebab-case slug задачи (3-30 символов, a-z 0-9 -)».
   - Sanitize: только `[a-z0-9-]`, не начинается/не заканчивается на `-`, длина 3-30.
   - Невалид → повторить запрос.

5. **Sync main с retry (3 попытки, backoff 2/4/8s, выводить ошибки каждой попытки):**
   ```bash
   git fetch origin
   git checkout main
   git pull --rebase origin main
   ```

6. **Создать ветку:**
   ```bash
   BRANCH="dev/${ALIAS}/${SLUG}"
   git checkout -b "$BRANCH"
   ```
   Если ветка с таким именем уже существует локально → ОТКАЗ: «Ветка $BRANCH уже есть. Используй другой slug или удали старую ветку».

7. **Audit-log:**
   ```bash
   sudo /usr/local/sbin/dev-audit-log dev-00-start "$BRANCH" "started task: $SLUG"
   ```

8. **Показать результат пользователю:**
   - Ветка, на каком коммите main она основана.
   - Напомнить: **один таск = один push**. Не смешивать задачи. Если по ходу заметишь другой баг — закончи эту задачу через `/dev-09-finish`, потом `/dev-00-start` под новый slug.

## Что НЕ делать

- Не стартовать с грязного WC — данные потеряются при rebase.
- Не использовать slug с пробелами, юникодом, или верхним регистром.
- Не реюзать существующее имя ветки — авто-инкремент скрывает путаницу.
