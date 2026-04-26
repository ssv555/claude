# Employers pipeline — runtime config (project-local)

> Per-project runtime flags for the global `emp-NN-*` skills. Lives at `<project>/.claude/skills/employers/config.md` (preferred) or `<project>/.docs/employers/config.md` (legacy back-compat). Each role reads this file at the start of its run and adapts behaviour.

## Flags

```yaml
use_subagents: false
# false = reports — каждый сотрудник работает в основном контексте Claude, читает/пишет файлы напрямую.
#         Плюсы: полная прозрачность, легко вмешаться. Минусы: основной контекст растёт.
# true  = subagents — оркестратор спавнит отдельный Agent-субагент на каждую роль с карточкой в промте.
#         Плюсы: основной контекст остаётся тонким. Минусы: меньше интерактивности, больше токенов суммарно.

interactive: true
# true  = оркестратор делает паузу после каждого этапа (BA → Architect → [Designer] → Developer → Reviewer)
#         и ждёт явного «ок / дальше / правки: <текст> / стоп» от пользователя.
# false = полный прогон без остановок; пользователь читает final.md в конце.

report_language: russian
# russian | english — язык отчётов pipeline (01_ba.md, 02_arch.md, 02b_design.md, 04_dev.md, 03_review.md, final.md).
# Карточки ролей всегда указывают модели, на каком языке писать отчёты.

default_subagent_type: general-purpose
# Тип Agent-субагента при use_subagents=true. Безопасный дефолт.

pipeline_root: .claude/skills/employers/pipeline
# Корневая папка для папок задач. Относительный путь от корня проекта.
# Каждая задача получает подпапку: <pipeline_root>/YYYY-MM-DD_<slug>/
#
# Legacy projects могут оставить пайплайн в `.docs/employers/pipeline` — глобальный SKILL.md
# принимает оба пути; здесь указывай тот, который реально используется в проекте.
```

## How skills consume these flags

Каждый `emp-NN-*` SKILL.md в начале запуска:
1. Resolves `EMPLOYERS_DIR` (preferred new path → legacy back-compat).
2. Reads this `config.md`.
3. Парсит YAML, применяет:
   - `use_subagents` → inline vs `Agent` спавн.
   - `interactive` → только оркестратор (другие игнорируют).
   - `report_language` → язык отчётов.
   - `default_subagent_type` → тип субагента у оркестратора.
   - `pipeline_root` → где создавать/искать папки задач.

## Changing flags

Просто отредактируй YAML выше. Перезапуск не нужен — следующий запуск любого `emp-*` подхватит новые значения.

## Runtime-триггер «Автопилот» (НЕ флаг здесь)

Режим «Автопилот» — **разовый триггер**, задаваемый пользователем в команде запуска, не постоянный флаг.

**Как включить на текущий запуск:** добавь в любое место команды `/emp-*` одно из ключевых слов (любой регистр):
- `автопилот`
- `autopilot`
- `--autopilot`
- `--auto`

**Что делает автопилот:**

1. Сотрудник НЕ задаёт вопросов пользователю.
2. Любая неоднозначность → «обоснованное допущение» в отчёт (вместо «Открытые вопросы / Блокеры»).
3. Pipeline не останавливается. Единственный жёсткий стоп — sealed-модули.
4. Оркестратор пропагирует режим спавнящимся субагентам.
5. `interactive` игнорируется при включённом автопилоте.

Полные правила — в карточке каждой роли (`~/.claude/skills/emp-NN-*/role.md`).

## Default rationale

- `use_subagents: false` — start transparent. Flip to `true` once you trust the pipeline and want to save main context on big tasks.
- `interactive: true` — catch mistakes early; reject bad BA before architect wastes effort.
- `report_language: russian` — reports are private notes between employees; pick what's natural for the team.

## Shared convention — Markdown-ссылки в отчётах

Один формат на всё не работает — проверено. Два контекста:

- **В чате с пользователем** → путь **от корня проекта**. Пример: `[auth.ts:42](back/src/middleware/auth.ts#L42)`. VSCode-чат резолвит от workspace root.
- **Внутри отчётов pipeline-папки** (`00_task.md`, `01_ba.md`, `02_arch.md`, `02b_design.md`, `03_review.md`, `04_dev.md`, `final.md`) → путь **от расположения md-файла**. Префикс `../` зависит от глубины `pipeline_root`. Например, для `pipeline_root: .docs/employers/pipeline` пайплайн-папка лежит на 4 уровня ниже корня → 4 раза `../`. Для `pipeline_root: .claude/skills/employers/pipeline` — 5 раз `../`.
  - Соседи в той же pipeline-папке: `[01_ba.md](./01_ba.md)`
  - Файлы проекта: `[auth.ts:42](<../>×N/back/src/middleware/auth.ts#L42)` (где N — глубина pipeline_root от корня)
  - VSCode в markdown-preview резолвит relative-to-file, НЕ от workspace root.
- **Общее:** без бэктиков вокруг путей; линковать только существующие на диске пути; несуществующие (планируемые к созданию) — plain-text в бэктиках без ссылки.

Точное число `../` для текущего проекта — фиксируй в `profile.md` → "Markdown link conventions" чтобы не пересчитывать каждый раз.

## Shared convention — Экономия токенов

Всем ролям: минимум болтовни, максимум смысла. Не пересказывай предыдущий отчёт своими словами — ссылайся. Таблицы и списки вместо абзацев.

## Shared rule — InProgress Board

Если в проекте есть `TODO.inprogress.md` (см. CLAUDE.md → "InProgress Board — Finish Protocol"), каждый сотрудник в конце своей роли (перед записью отчёта) обновляет его — секция "Employees (emp-*)". Если файла или раздела нет в проекте — пропустить.
