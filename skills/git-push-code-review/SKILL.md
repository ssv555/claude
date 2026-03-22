---
name: git-push-code-review
description: Generate git command for add + commit + push with code review
disable-model-invocation: false
allowed-tools: Bash(git *), Read, Edit, AskUserQuestion, Agent(code-reviewer), WebFetch
model: sonnet
---

Generate a `git add -A && git commit -m "msg" && git pull --rebase && git push` command.

<!-- pull --rebase added for safe parallel work: when multiple developers push to the same branch,
     rebase pulls remote changes before push. For solo work it's a no-op (nothing to rebase). -->

## Execution

1. Run `git status` and `git diff`
2. **Code Review**: Launch the `code-reviewer` agent to review all changes.
   - If agent returns "Замечаний нет" → continue to step 3
   - If agent returns issues → output ALL issues as formatted text to the user FIRST, THEN call AskUserQuestion:
     ```json
     {
       "questions": [{
         "question": "Code review нашёл замечания (см. выше). Что делать?",
         "header": "Code Review",
         "options": [
           {"label": "Продолжить push", "description": "Игнорировать замечания и пушить"},
           {"label": "Остановить", "description": "Прервать push, исправить замечания"}
         ],
         "multiSelect": false
       }]
     }
     ```
   - If user chose "Остановить" → output "Push отменён. Исправьте замечания и вызовите /git-push-code-review снова." and STOP.
3. Check if any changed file matches these cached paths:
   - `expenses_front/public/locales/`
   - `server/shared/constants.ts`
   - `server/db/schema/categories.ts`
   - `server/routes/categories.ts`
   - `server/routes/codes.ts`
4. If ANY match found:
   a. Read `server/shared/version.ts` to get current APP_VERSION
   b. Fetch production version: `WebFetch` URL `https://iamrich.it-joy.ru/api/version`. Extract `version` field from JSON response. If fetch fails or times out — use `"недоступен"`
   c. Call the AskUserQuestion tool:

```json
{
  "questions": [{
    "question": "Обновить версию? (локальная: <VERSION>, прод: <PROD_VERSION>). Изменены кэшируемые файлы: <FILES>",
    "header": "Version",
    "options": [
      {"label": "Да (+0.001)", "description": "Инкремент patch версии"},
      {"label": "Нет", "description": "Оставить текущую"}
    ],
    "multiSelect": false
  }]
}
```

Replace `<FILES>` with matched filenames, comma-separated (e.g. `locales/en/translation.json, locales/ru/translation.json`).
Replace `<VERSION>` with the actual APP_VERSION value from version.ts (e.g. `1.0.015`).
Replace `<PROD_VERSION>` with the version from production API response, or `недоступен` if fetch failed.

Do NOT edit any files until user responds.

5. If user chose "Да": read `server/shared/version.ts`, increment patch (e.g. 1.0.014 → 1.0.015), edit file, append `(v1.0.015)` to commit message
6. Output SHORT commit message (3-5 words, english, prefix: fix/add/update/refactor/remove) as:

```bash
git add -A && git commit -m "message" && git pull --rebase && git push
```

No text before or after the code block.
