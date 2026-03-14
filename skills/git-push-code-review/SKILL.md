---
name: git-push-code-review
description: Generate git command for add + commit + push with code review
disable-model-invocation: false
allowed-tools: Bash(git *), Read, Edit, AskUserQuestion, Agent(code-reviewer)
model: sonnet
---

Generate a `git add -A && git commit -m "msg" && git push` command.

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
4. If ANY match found: first read `server/shared/version.ts` to get current APP_VERSION, then call the AskUserQuestion tool:

```json
{
  "questions": [{
    "question": "Обновить версию? (текущая: <VERSION>). Изменены кэшируемые файлы: <FILES>",
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
Replace `<VERSION>` with the actual APP_VERSION value (e.g. `1.0.015`).

Do NOT edit any files until user responds.

5. If user chose "Да": read `server/shared/version.ts`, increment patch (e.g. 1.0.014 → 1.0.015), edit file, append `(v1.0.015)` to commit message
6. Output SHORT commit message (3-5 words, english, prefix: fix/add/update/refactor/remove) as:

```bash
git add -A && git commit -m "message" && git push
```

No text before or after the code block.
