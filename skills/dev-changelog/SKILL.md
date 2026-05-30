---
name: dev-changelog
description: Chief-only — analyze what a developer's branch changed vs main. Takes a HEAD sha (from TG notification or /dev-merge <alias> table), finds the branch, fetches the diff, and produces a structured report: Technical changes (files, routes, DB, components) + Business changes (features, fixes, user-facing impact). Use when user says "/dev-changelog <sha>", "что сделал дев", "анализ ветки".
model: opus
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*)
---

# dev-changelog

Анализ изменений dev-ветки относительно `main`. **Только шеф (ssv555 / PC-SKY).**

## Status block

```
SKILL:  dev-changelog
MODEL:  opus
```

## Доступ — только шеф

```powershell
if (-not (($env:USERNAME -eq 'ssv555') -or ($env:COMPUTERNAME -eq 'PC-SKY'))) {
    Write-Error "Forbidden: chief-only skill"
    exit 1
}
```

## Аргумент

`/dev-changelog <sha>` — short sha из TG-нотификации или из `/dev-merge <alias>` таблицы.

## Алгоритм

1. **Найти ветку по sha** на moscow_my (так же как в `/dev-merge`):
   ```bash
   ssh moscow_my "git -C /srv/git/VDole.git for-each-ref \
     --format='%(objectname:short) %(refname:short)' refs/heads/dev/ | grep '^<sha>'"
   ```
   Нет → «ветка не найдена (возможно уже смерджена — можно смотреть через `git log` на main)».

2. **Получить diff между main и веткой:**
   ```bash
   git remote add moscow ssh://ssv@moscow_my:53847/srv/git/VDole.git  # если нет
   git fetch moscow dev/<alias>/<slug>
   git diff origin/main...FETCH_HEAD
   ```
   Также:
   ```bash
   git log --oneline origin/main..FETCH_HEAD
   git diff --stat origin/main...FETCH_HEAD
   ```

3. **Прочитать полный diff** — все изменённые файлы.

4. **Составить структурированный отчёт:**

---

### Структура отчёта

```
## Branch: dev/<alias>/<slug>
sha: <sha>  ·  <N> commits  ·  +X/-Y lines

### Commits
• <subject 1>
• <subject 2>
...

### Technical changes
#### Backend
- <file>: <что изменено — новый endpoint / изменена логика / новая функция>
- ...

#### Frontend
- <file>: <новый компонент / изменён UI / новый хук>
- ...

#### Database
- <новая таблица / новые колонки / изменены индексы>  (если есть)

#### Config / Infrastructure
- <изменения в .env шаблонах, nginx, CI, scripts>  (если есть)

### Business changes
<Что именно изменилось с точки зрения пользователя / бизнес-логики.
Например: «Добавлена возможность сброса пароля по email» или
«Исправлена ошибка: инвестор не видел свои дивиденды после смены email».
Конкретно, без техжаргона. Если изменение чисто техническое (рефакторинг,
тест, инфра) — написать «Техническое: <суть>».>

### Risk assessment
<Что может сломаться при мердже: зависимые модули, shared state,
миграции БД, breaking API changes, изменения auth-flow.
Если нет рисков — «Низкий: изолированное изменение».>
```

---

5. **После отчёта** — один из двух хинтов:
   - Если выглядит чисто: «Готово к мерджу → `/dev-merge <sha>`»
   - Если есть вопросы: «Перед мерджем стоит уточнить у дева: <вопрос>»

## Что НЕ делать

- Не мерджить — только анализировать.
- Не читать `.env.development` (секреты не нужны для анализа diff'а).
- Не показывать в отчёте значения секретов даже если они попали в diff — только факт «добавлена переменная X».