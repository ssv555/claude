# Report template — dev-sessions-analyze

Заполни плейсхолдеры `{{NAME}}`, запиши в `D:\Data\Documents\Programming\Projects\WEB\VDole\.docs\dev\sessions\<alias>_<YYYY-MM-DD>_<sid_short>.md`.

---

```markdown
# Dev session analysis — {{ALIAS}} — {{DATE}}

**Dev alias:** {{ALIAS}}
**Full name:** {{FULL_NAME}}
**Session ID:** {{SESSION_ID}}
**Session topic:** {{TOPIC}}
**Source file:** `{{JSONL_PATH}}` ({{SIZE_HUMAN}})
**Date range:** {{FIRST_TS}} — {{LAST_TS}} ({{TIMEZONE}})

---

## Session statistics — сама сессия дева

| | |
|---|---|
| Messages | {{MSG_COUNT}} (user {{USER_MSGS}} / assistant {{ASSIST_MSGS}}) |
| Tool calls | {{TOOL_TOTAL}} ({{TOOL_BREAKDOWN}}) |
| Tokens (dev's session) | input {{TOK_IN}} · cache {{TOK_CACHE}} · output {{TOK_OUT}} · **total {{TOK_TOTAL}}** |
| Wall-clock duration | {{WALL_CLOCK}} |
| Estimated active time | **{{ACTIVE_TIME}}** (gaps >5min capped at 5min) |
| Idle/break time | {{IDLE_TIME}} ({{IDLE_BREAKS}} breaks) |

---

## Quality assessment — 10 dimensions

Каждой метрике балл 1-10 (1 = очень слабо, 5 = средне, 10 = идеально).
Полное описание методики — `~/.claude/skills/dev-sessions-analyze/METRICS.md`.

### 1. Test/verification rate — {{SCORE_1}}/10

{{COMMENT_1}}

**Примеры:**
- ✓ {{EXAMPLE_1_GOOD}}
- ✗ {{EXAMPLE_1_BAD}}

### 2. Iteration cycles — {{SCORE_2}}/10

{{COMMENT_2}}

**Примеры:** {{EXAMPLE_2}}

### 3. Tool diversity — {{SCORE_3}}/10

Использовал: {{TOOLS_USED_LIST}}.
Не трогал: {{TOOLS_MISSED}}.

{{COMMENT_3}}

### 4. AI correction rate — {{SCORE_4}}/10

Поправил AI {{CORRECTION_COUNT}} раз из {{TOTAL_USER_MSGS}} сообщений ({{CORRECTION_PCT}}%).

{{COMMENT_4}}

**Примеры:** {{EXAMPLE_4}}

### 5. Continuity — {{SCORE_5}}/10

{{COMMENT_5}} ({{TASKS_FINISHED}}/{{TASKS_TOTAL}} задач доведено до явной резолюции)

### 6. Project ownership signs — {{SCORE_6}}/10

{{COMMENT_6}}

- Обновлений personal memory: {{MEMORY_WRITES}}
- Ссылок на CLAUDE.md / project conventions: {{CLAUDE_REFS}}
- Качество commit-messages: {{COMMIT_QUALITY}}

### 7. Active time at keyboard — {{SCORE_7}}/10

**Реальное время за работой: {{ACTIVE_TIME}}** (для зарплаты-ориентира).

Wall-clock {{WALL_CLOCK}}, из них активно {{ACTIVE_TIME}}, перерывов {{IDLE_TIME}}.

### 8. Work pattern — {{SCORE_8_OR_NA}}

{{COMMENT_8}}

(Эта метрика **не для критики** — только информация.)

### 9. Pushback maturity — {{SCORE_9}}/10

{{PUSHBACK_WITH_REASON}} из {{PUSHBACK_TOTAL}} pushback'ов с обоснованием.

{{COMMENT_9}}

**Хорошие примеры:** {{EXAMPLE_9_GOOD}}
**Слабые:** {{EXAMPLE_9_BAD}}

### 10. Self-validation — {{SCORE_10}}/10

Сам проверил факт {{VALIDATED_COUNT}} раз (открыл файл / запустил команду / посмотрел результат) vs повторил AI-вывод без проверки.

{{COMMENT_10}}

---

## Итоговая оценка

**Engagement: {{ENGAGEMENT_PCT}}%** — вовлечённость в проект.
**AI usage quality: {{AI_QUALITY_PCT}}%** — качество промпт-инжиниринга.
**Средний балл: {{AVG_SCORE}}/10.**

{{VERDICT_ONE_LINE}}

---

## Рекомендации (от имени шефа, лояльно)

{{LOYAL_RECOMMENDATIONS}}

---

## Analyzer cost — затраты на сам анализ (твоя session шефа)

| | |
|---|---|
| Tokens (analyzer = chief's session) | input {{ANAL_TOK_IN}} · cache {{ANAL_TOK_CACHE}} · output {{ANAL_TOK_OUT}} · **total {{ANAL_TOK_TOTAL}}** |
| Wall-clock (analysis duration) | {{ANAL_WALL_CLOCK}} |
| Subagents spawned | {{SUBAGENT_COUNT}} |
| Model | opus 4.7 (1M context) |

---

*Generated: {{NOW_TS}} by /dev-sessions-analyze*
```

## Notes

- Все плейсхолдеры с числами форматируй: `1,234` (с разделителем) или `1.2k` для тысяч, `2.3M` для миллионов.
- `ACTIVE_TIME` и `WALL_CLOCK` — `Nh Mm` (например `3h 47m`).
- Если метрика не применима (сессия слишком короткая, нет данных) — балл `N/A` и комментарий «недостаточно данных».
- `VERDICT_ONE_LINE` — одна фраза, например: «Крепкая работа, основные привычки в порядке, рекомендую держать темп».
- `LOYAL_RECOMMENDATIONS` — 3-5 пунктов, каждый начинается с конкретного наблюдения и заканчивается «попробуй / так держать / в следующий раз». Без оценочных «плохо», «не годится», «не профессионально».
