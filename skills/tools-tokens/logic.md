# KTU Analysis — Developer Contribution & Code Complexity

> **КТУ** — Коэффициент Трудового Участия. Скилл анализирует git-историю проекта
> и рассчитывает процентный вклад каждого разработчика с учётом объёма и сложности кода.
> Метод: гибридный — Weighted LOC × (1 + Logic Density).

Execute ALL steps strictly in order. Do NOT run steps in parallel. Complete each step before starting the next.

---

## Configuration

### Report File

> Путь к файлу отчёта. Хранит результаты всех запусков и метку даты последнего анализа.
> Лежит ВНУТРИ проекта в его `.claude/` — у каждого проекта свой отчёт. Обычно `.claude/*` в `.gitignore`, поэтому отчёт вне VCS.

```
REPORT_FILE   = {project_root}/.claude/tokens-report.md
PROJECT_NAME  = basename "$(git -C {project_root} rev-parse --show-toplevel)"
```

`{project_root}` — текущая рабочая директория беседы (обычно корень репозитория). Если каталог `{project_root}/.claude/` отсутствует — создать его перед первой записью отчёта.

### Author Alias Map

> **Карта авторов.** Один разработчик может коммитить под разными именами, но email один. Группируем по email → каноническое имя.

| Email | Canonical Name |
|-------|---------------|
| ssv555@mail.ru | ssv555 |
| whitedullahan@gmail.com | Kirill |
| 55056945+WhiteDullahan@users.noreply.github.com | Kirill |

If a new email appears that is NOT in this map, use the git author name as-is and note it in the output as "NEW AUTHOR — add to alias map" (either in this file for global default, or in `{project_root}/.claude/tokens-config.md` for a per-project override — see SKILL.md §3).

**Per-project override of the alias map**: If `{project_root}/.claude/tokens-config.md` exists and contains its own `## Author Alias Map` section in the same `| Email | Canonical Name |` table format, USE THAT MAP INSTEAD of the default above. This is checked once at the start of the run; format mismatches → fall back to the default and warn once in chat. The override file may also be empty or contain only commentary — in that case the default is used.

### File Type Weights

> **Весовые коэффициенты типов файлов.** Не все строки кода одинаково ценны (бизнес-логика .ts = 1.0, конфиги .json = 0.2, автоген = 0.02, бинарники = 0.0).
> Формула: `строки × вес = взвешенный объём`

| Pattern | Weight | Category |
|---------|--------|----------|
| `*.ts`, `*.tsx` | 1.0 | Core logic |
| `*.js` | 0.8 | JavaScript |
| `*.sql` | 0.8 | Database |
| `*.sh`, `*.ps1` | 0.7 | Scripts |
| `*.css` | 0.4 | Styles |
| `*.html` | 0.4 | Markup |
| `*.bat`, `*.cmd` | 0.3 | Windows scripts |
| `*.json` (not lock/not package-lock) | 0.2 | Config |
| `*.toml`, `*.xml`, `*.yaml`, `*.yml` | 0.2 | Config |
| `*.md` | 0.15 | Docs |
| `*.gitignore`, `*.gitkeep`, `*.gitattributes` | 0.05 | Git meta |
| `bun.lock`, `*.lock`, `package-lock.json` | 0.05 | Lockfiles |
| `*.gen.ts`, `*.gen.js`, `routeTree.gen.ts` | 0.02 | Auto-generated |
| `*.webp`, `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.svg`, `*.ico`, `*.woff`, `*.woff2`, `*.ttf`, `*.eot` | 0.0 | Binary |

If a file extension is not listed, use weight **0.5** (unknown type, moderate weight).

### Complexity Keywords

> **Ключевые слова для анализа плотности логики.** Считаем "умные" конструкции на строку кода — чем больше, тем выше logic density.

**Control flow** (+0.1 each): `if`, `else`, `for`, `while`, `switch`, `case`
**Error handling** (+0.1 each): `try`, `catch`, `throw`
**Functions** (+0.05 each): `function`, `async`, `=>`
**Ternary** (+0.05): line contains `?` followed by `:`
**Nesting**: each indentation level beyond 2 (measured as 2-space or 1-tab units) → +0.05

### Complexity Rating Scale

> **Шкала сложности.** Итоговый рейтинг по средней плотности логики: Low (конфиги/доки), Medium (компоненты/CRUD), High (алгоритмы/state), Expert (middleware/парсеры).

| Avg Logic Density | Rating |
|-------------------|--------|
| 0.0 – 0.3 | Low |
| 0.3 – 0.6 | Medium |
| 0.6 – 1.0 | High |
| 1.0+ | Expert |

### Effort Estimation (COCOMO Basic Organic)

> **Оценка трудозатрат по COCOMO Basic, режим Organic** (Boehm 1981) — отраслевой стандарт для расчёта человеко-часов по объёму кода. Назначение: «сколько бы заняло вручную без ИИ». Экспонента `1.05` отражает нелинейный рост сложности с ростом кодовой базы.
>
> Формула:
> ```
> effective_loc = weighted_loc × (1 + logic_density)
> KLOC          = effective_loc / 1000
> PM            = 2.4 × KLOC^1.05    # person-months (человеко-месяцы)
> hours         = PM × 152           # 1 PM = 152 часа (стандарт COCOMO: 19 дней × 8ч)
> days          = floor(hours / 8)   # 1 рабочий день = 8 часов
> rem_hours     = round(hours - days × 8)
> ```

**COCOMO constants (Organic mode):**

| Constant | Value | Meaning |
|----------|-------|---------|
| `COCOMO_A` | 2.4 | Scale coefficient (Organic) |
| `COCOMO_B` | 1.05 | Exponent (Organic) |
| `HOURS_PER_PM` | 152 | Hours in one person-month |
| `HOURS_PER_DAY` | 8 | Working hours in one day |

---

## Step 0: Resolve project name and overrides

> Скилл глобальный — до git-команд зафиксировать имя текущего проекта и подхватить per-project overrides.

1. **Resolve `PROJECT_NAME`** via Bash (single command):
   ```bash
   basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
   ```
   Store the result as `PROJECT_NAME`. Used in the report header (Step 9).

2. **Optional alias map override**:
   - Try to Read `{project_root}/.claude/tokens-config.md`.
   - If it exists AND contains a section header `## Author Alias Map` followed by a table with the same `| Email | Canonical Name |` schema as the default in this file — use THAT map for the rest of the run.
   - If the file is missing, empty, or the section header is absent → use the default map silently.
   - If the section is present but malformed (broken table, missing columns) → fall back to default and emit one warning line in chat: *«⚠ tokens-config.md: Author Alias Map malformed, using default»*. Continue.

3. **Ensure `{project_root}/.claude/` exists** — if the directory is missing, create it before any later step that writes the report.

---

## Step 1: Read Previous State

> Читаем дату последнего анализа из файла отчёта.
> Если файла нет — это первый запуск, анализируем всю историю с начала.

1. Read the file at `REPORT_FILE` using the Read tool
2. If the file does not exist or is empty:
   - Set `LAST_DATE` = `null` (analyze entire history)
   - Set `HISTORICAL_ROWS` = `[]` (no history)
3. If the file exists:
   - Search for the LAST line matching pattern: `<!-- LAST_ANALYSIS_DATE: YYYY-MM-DDTHH:MM:SS+ZZ:ZZ -->`
   - Extract the ISO 8601 timestamp as `LAST_DATE`
   - **Parse historical rows**: Find the last section's `### Cumulative Developer Breakdown` table. Extract all data rows (lines starting with `|` that are NOT the header, separator, or Итого row). Parse each into: `{ period, developer, commits, added, removed, wloc, density, complexity, score, contribution_pct, time_str, hours }`. Store as `HISTORICAL_ROWS[]`. If no cumulative table found (old format), parse ALL `### Developer Breakdown` tables from ALL sections instead, calculating Time from W.LOC and Density using COCOMO formula.
   - These rows carry forward into the new cumulative section without recalculation.

---

## Step 2: Freeze Timestamp

> **Замораживаем текущее время ДО анализа.** Коммит, сделанный во время анализа, не потеряется — его подхватит следующий запуск (`ANALYSIS_TIMESTAMP` зафиксирован раньше).

**CRITICAL**: This MUST happen BEFORE any git commands.

Run via Bash:
```bash
date --iso-8601=seconds
```

Store result as `ANALYSIS_TIMESTAMP`.

---

## Step 3: Count Total Commits (including merges, for reporting)

> Считаем общее число коммитов и отдельно merge-коммиты.
> Merge-коммиты исключаются из анализа (они дублируют изменения), но показываем их число в отчёте.

Run via Bash:
```bash
git log --oneline [--since="LAST_DATE"] --until="ANALYSIS_TIMESTAMP" | wc -l
```

Store as `TOTAL_COMMITS_WITH_MERGES`.

Then count merge commits:
```bash
git log --oneline --merges [--since="LAST_DATE"] --until="ANALYSIS_TIMESTAMP" | wc -l
```

Store as `MERGE_COMMITS`.

---

## Step 4: Extract Commit Data

> Извлекаем данные коммитов: автор, email, дата, файлы с added/removed.
> `--no-merges` — не считать строки дважды; `--numstat` — точное added/removed на файл. Коммиты feature-веток видны (после merge они часть истории main).

Build and run ONE git command:

**If LAST_DATE is null (first run)**:
```bash
git log --no-merges --numstat --format="COMMIT_START|%H|%an|%ae|%aI" --until="ANALYSIS_TIMESTAMP"
```

**If LAST_DATE exists (incremental)**:
```bash
git log --no-merges --numstat --format="COMMIT_START|%H|%an|%ae|%aI" --since="LAST_DATE" --until="ANALYSIS_TIMESTAMP"
```

**Parse output** into a data structure:
- Line starting with `COMMIT_START|` → new commit: `{ hash, author_name, author_email, date, files: [] }`
- Subsequent lines with tab-separated values `added\tremoved\tfilename`:
  - If added == "-" AND removed == "-" → binary file, skip (score = 0)
  - Otherwise → `{ filename, added: int, removed: int }`
- Empty lines → ignore

**If zero non-merge commits found** → output "No new commits found since last analysis (LAST_DATE)" and STOP. Do not save report.

---

## Step 5: Calculate Weighted LOC per Commit

> **W.LOC (Weighted Lines of Code)** — взвешенный объём кода.
>
> На файл: `file_weighted_loc = (added + removed × 0.5) × weight` (removed с коэфф. 0.5 — удаление требует понимания, но не создаёт нового кода; weight из таблицы выше).
> На коммит: `commit_weighted_loc = SUM(file_weighted_loc)`

For each commit, for each file:

1. Extract file extension from filename
2. Special cases (check BEFORE extension):
   - Filename contains `bun.lock` → weight 0.05
   - Filename contains `.gen.ts` or `.gen.js` or `routeTree.gen.ts` → weight 0.02
   - Filename contains `package-lock.json` → weight 0.05
3. Look up weight from File Type Weights table by extension
4. If extension not found → weight 0.5
5. Calculate: `file_weighted_loc = (added + removed × 0.5) × weight`
6. Sum across all files in commit: `commit_weighted_loc = SUM(file_weighted_loc)`

---

## Step 6: Calculate Logic Density per Commit

> **Logic Density (Плотность логики)** — насколько "умный" код в коммите.
>
> Анализируем ТОЛЬКО добавленные строки diff (начинающиеся с `+`, исключая `+++`). Считаем ключевые слова.
> Формула: `logic_density = сумма_очков_ключевых_слов / кол-во_добавленных_строк`. Пустой коммит → density = 0.
>
> **Score:** `commit_score = commit_weighted_loc × (1 + logic_density)` — множитель повышает вес сложного кода (конфиг density≈0 → ×1.0; логика density≈0.5 → ×1.5).

For each commit with `commit_weighted_loc > 0`:

Batch commits into groups of 5 to minimize Bash calls. Run:

```bash
for hash in HASH1 HASH2 HASH3 HASH4 HASH5; do
  echo "=HASH=$hash"
  git show --format="" -p "$hash" | grep "^+" | grep -v "^+++" > /tmp/ktu_diff_$hash.txt
  echo "CONTROL:$(grep -cE '\b(if|else|for|while|switch|case)\b' /tmp/ktu_diff_$hash.txt 2>/dev/null || echo 0)"
  echo "ERROR:$(grep -cE '\b(try|catch|throw)\b' /tmp/ktu_diff_$hash.txt 2>/dev/null || echo 0)"
  echo "FUNC:$(grep -cE '\bfunction\b|\basync\b|=>' /tmp/ktu_diff_$hash.txt 2>/dev/null || echo 0)"
  echo "TERNARY:$(grep -cE '\?.*:' /tmp/ktu_diff_$hash.txt 2>/dev/null || echo 0)"
  echo "LINES:$(wc -l < /tmp/ktu_diff_$hash.txt 2>/dev/null || echo 0)"
  rm -f /tmp/ktu_diff_$hash.txt
done
```

Parse output per commit:
- `control_score = CONTROL × 0.1`
- `error_score = ERROR × 0.1`
- `func_score = FUNC × 0.05`
- `ternary_score = TERNARY × 0.05`
- `logic_density = (control_score + error_score + func_score + ternary_score) / max(LINES, 1)`
- `commit_score = commit_weighted_loc × (1 + logic_density)`

Note: Nesting analysis is omitted from batch for simplicity. The keyword density provides a good approximation.

---

## Step 7: Aggregate per Developer

> **Агрегация по разработчикам.** Суммируем все коммиты каждого автора.
>
> - **Period** — период анализа (`FROM_DATE — TO_DATE`), одинаковый для всех строк запуска
> - **Commits** — число коммитов разработчика
> - **Added/Removed** — сырые строки (без весов), для справки
> - **W.LOC** — суммарный взвешенный объём
> - **Score** — итоговый балл = W.LOC с учётом сложности
> - **Avg Logic Density** — средневзвешенная: `SUM(density × W.LOC) / SUM(W.LOC)` (большие коммиты влияют сильнее)
> - **Contribution %** — `(score_разработчика / score_всех) × 100%`, в сумме = 100%
> - **Complexity** — рейтинг (Low/Medium/High/Expert) по avg density

1. Map each commit's `author_email` to canonical name using the Author Alias Map
2. For each developer, calculate:
   - `total_commits` = count of their commits
   - `total_added` = sum of raw added lines across all files
   - `total_removed` = sum of raw removed lines across all files
   - `total_weighted_loc` = sum of commit_weighted_loc
   - `total_score` = sum of commit_score
   - `avg_logic_density` = weighted average: `SUM(logic_density × commit_weighted_loc) / SUM(commit_weighted_loc)`
3. Calculate `contribution_pct = (developer_total_score / global_total_score) × 100`
4. Determine `complexity_rating` from avg_logic_density using the Complexity Rating Scale
5. Calculate effort estimate (COCOMO Basic Organic) per developer:
   - `effective_loc = total_weighted_loc × (1 + avg_logic_density)`
   - `kloc = effective_loc / 1000`
   - If `kloc == 0` → `hours = 0`
   - Else → `pm = 2.4 × kloc^1.05`, `hours = pm × 152`
   - `days = floor(hours / 8)`
   - `rem_hours = round(hours - days × 8)`
   - If `rem_hours == 8` → `days += 1, rem_hours = 0` (rounding edge case)
   - Format `time_str`:
     - If `days == 0 and rem_hours == 0` → `"0ч"`
     - If `days == 0` → `"{rem_hours}ч"`
     - If `rem_hours == 0` → `"{days}д"`
     - Otherwise → `"{days}д {rem_hours}ч"`
6. **Build cumulative table rows**:
   - `CURRENT_ROWS` = rows from steps 1-5 above (current run, each has Period = `FROM_DATE — TO_DATE`)
   - `ALL_ROWS` = `HISTORICAL_ROWS` (from Step 1) + `CURRENT_ROWS`
   - Recalculate `contribution_pct` for each row: `row.score / SUM(all_rows.score) × 100`
   - Calculate **Итого** row (sum across ALL rows, all periods):
     - `total_commits_all = SUM(all_rows.commits)`
     - `total_added_all = SUM(all_rows.added)`
     - `total_removed_all = SUM(all_rows.removed)`
     - `total_weighted_loc_all = SUM(all_rows.wloc)`
     - `total_score_all = SUM(all_rows.score)`
     - `total_hours_all = SUM(all_rows.hours)` — sum of COCOMO hours from ALL rows
     - Convert `total_hours_all` to `total_time_str` using days/hours formula
     - Non-summable fields in Итого row: `Period` = `—`, `Density` = `—`, `Complexity` = `—`, `Contribution %` = `100.0%`
   - **Итого is meaningful** because it sums ALL periods. A single-period run's Итого is trivially equal to the sum of its rows, but grows with each subsequent run.

---

## Step 8: Output Results to User

> Выводим итоговую таблицу в чат. Сортировка по Contribution % — кто внёс больше, тот сверху.

Display in chat the **cumulative table** — all periods, not just the current run:

```
## KTU Report — Cumulative (FIRST_PERIOD_START — ANALYSIS_TIMESTAMP)

| Period | Developer | Commits | W.LOC | Score | Contribution % | Complexity | Time     |
|--------|-----------|---------|-------|-------|----------------|------------|----------|
| period1 dates | name1 | N | XXXX | XXXX | XX.X% | Low | 5д 3ч |
| period1 dates | name2 | N | XXX  | XXX  | X.X%  | Low | 2ч    |
| period2 dates | name1 | N | XXXX | XXXX | XX.X% | Low | 3д 1ч |
| ...           | ...   | ... | ... | ... | ...   | ... | ...   |
| — | **Итого** | **N** | **XXXX** | **XXXX** | **100.0%** | — | **XXд Xч** |

Current run: N commits (merge excluded: M)
Cumulative: N commits across K periods

> *Time = COCOMO Basic Organic estimate (manual effort without AI).*
> *Итого — суммарная ручная трудоёмкость за все периоды.*
```

Rows are ordered chronologically by Period, then by Contribution % within same period.
The **Итого** row is always last. It sums ALL rows across ALL periods.
Format percentages to 1 decimal place (contribution is recalculated as row_score / total_all_scores).

---

## Step 9: Save Report

> Сохраняем отчёт в файл. Каждый запуск добавляет новую секцию. Последняя строка файла — дата анализа в HTML-комментарии, её читает Step 1 при следующем запуске.

1. Read existing `REPORT_FILE` content (or empty string if first run)
2. If first run (file does not exist), create the file with the header and field descriptions block first:

```markdown
# KTU Report — {PROJECT_NAME} Project

> **КТУ** — Коэффициент Трудового Участия.
> Метод: гибридный — Weighted LOC x (1 + Logic Density).
> Оценка трудозатрат: COCOMO Basic Organic (Boehm 1981).

### Расшифровка полей

| Поле | Описание |
|------|----------|
| **Period** | Период анализа (`FROM_DATE — TO_DATE`). Все строки внутри одной секции имеют одинаковый Period — это период между предыдущим запуском КТУ и текущим. Нужен чтобы не терять контекст при просмотре одиночной строки вне секции |
| **Developer** | Каноническое имя разработчика (группировка по email) |
| **Commits** | Количество коммитов (merge-коммиты исключены) |
| **Added** | Сырое количество добавленных строк (без весов) |
| **Removed** | Сырое количество удалённых строк (без весов) |
| **W.LOC** | Weighted Lines of Code — взвешенный объём. Формула: `(added + removed x 0.5) x вес_типа_файла`. Удалённые строки считаются с коэфф. 0.5 (удаление требует понимания, но не создаёт нового кода) |
| **Density** | Logic Density — плотность логики. Отношение логических конструкций (if/for/try/catch/=>) к общему числу добавленных строк. Чем выше — тем "умнее" код |
| **Complexity** | Рейтинг сложности на основе Density: Low (0-0.3), Medium (0.3-0.6), High (0.6-1.0), Expert (1.0+) |
| **Score** | Итоговый балл: `W.LOC x (1 + Density)`. Множитель повышает вес сложного кода |
| **Contribution %** | Долевое участие: `score_разработчика / score_всех x 100%`. Все в сумме = 100% |
| **Time** | Оценка трудозатрат по COCOMO Basic Organic: `PM = 2.4 × KLOC^1.05`, где `KLOC = W.LOC × (1 + Density) / 1000`; `1 PM = 152ч`, `1 день = 8ч`. Покрывает полный цикл (проектирование, код, отладка, тесты, интеграция). Показывает, сколько бы заняло вручную, без ИИ. Строка **Итого** — суммарная ручная трудоёмкость всей работы |
```

**Backfill field description on incremental run**: If the report file already exists but its "Расшифровка полей" table does NOT contain a `**Time**` row, insert the Time row (exact markdown shown above) immediately after the `**Contribution %**` row. Similarly, if it does NOT contain a `**Period**` row, insert the Period row (exact markdown shown above) immediately before the `**Developer**` row. This keeps old reports' field legend in sync with the new format.

3. If file exists and has content, remove the **entire last section** (from the last `## Analysis:` heading to the end of file, including the `<!-- LAST_ANALYSIS_DATE: ... -->` line). Previous per-period sections (before the last one) are kept as historical snapshots.
4. Append the following new **cumulative** section:

```markdown

---

## Analysis: YYYY-MM-DD HH:MM

**Current period**: FROM_DATE — TO_DATE
**Commits (current run)**: N (merges excluded: M)
**Cumulative commits**: TOTAL_N

### Cumulative Developer Breakdown

| Period | Developer | Commits | Added | Removed | W.LOC | Density | Complexity | Score | Contribution % | Time |
|--------|-----------|---------|-------|---------|-------|---------|------------|-------|----------------|------|
| period1 | name1 | N | XXXX | XXXX | XXXX | 0.XX | Low | XXXX | XX.X% | 5д 3ч |
| period1 | name2 | N | XXX  | XXX  | XXX  | 0.XX | Low | XXX  | X.X%  | 2ч    |
| period2 | name1 | N | XXXX | XXXX | XXXX | 0.XX | Low | XXXX | XX.X% | 3д 1ч |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |
| — | **Итого** | **N** | **XXXX** | **XXXX** | **XXXX** | — | — | **XXXX** | **100.0%** | **XXд Xч** |

> *Time = оценка по COCOMO Basic Organic (`PM = 2.4 × KLOC^1.05`, `1 PM = 152ч`, `1 день = 8ч`). Показывает ручную трудоёмкость без ИИ. Строка **Итого** — суммарная ручная трудоёмкость за все периоды.*

<details>
<summary>Current run commit details (click to expand)</summary>

| Hash | Author | Date | Files | Added | Removed | W.LOC | Density | Score |
|------|--------|------|-------|-------|---------|-------|---------|-------|
| abc1234 | name1 | 2026-03-20 | 5 | 100 | 20 | 95.0 | 0.35 | 128.3 |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |

</details>

<!-- LAST_ANALYSIS_DATE: ANALYSIS_TIMESTAMP -->
```

**Key difference from old format**: the last section is always **cumulative** — it contains ALL historical period rows (from `HISTORICAL_ROWS`) plus the current run's rows. Previous per-period sections remain as snapshots. On each new run, the previous cumulative section is replaced with an updated one that includes the new period.

5. Write the complete content to `REPORT_FILE` using the Write tool

---

## Step 10: Output Link

> Даём пользователю кликабельную ссылку на файл отчёта, чтобы открыть в IDE.

After saving, output to the user (relative path from project root):

```
Report saved: [tokens-report.md](.claude/tokens-report.md)
```
