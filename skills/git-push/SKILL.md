---
name: git-push
description: Generate git command for add + commit + push
disable-model-invocation: false
allowed-tools: Bash(git *), Read, Edit, AskUserQuestion, WebFetch
model: sonnet
---

Generate a `git add -A && git commit -m "msg" && git push` command.

## Execution

1. Run `git status` and `git diff`
2. Check if any changed file matches these cached paths:
   - `expenses_front/public/locales/`
   - `server/shared/constants.ts`
   - `server/db/schema/categories.ts`
   - `server/routes/categories.ts`
   - `server/routes/codes.ts`
3. If ANY match found:
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

4. If user chose "Да": read `server/shared/version.ts`, increment patch (e.g. 1.0.014 → 1.0.015), edit file, append `(v1.0.015)` to commit message
5. Output SHORT commit message (3-5 words, english, prefix: fix/add/update/refactor/remove) as:

```bash
git add -A && git commit -m "message" && git push
```

No text before or after the code block.
