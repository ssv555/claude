---
name: git-push
description: Generate git command for add + commit + push
disable-model-invocation: false
allowed-tools: Bash(git *), Read, Edit, AskUserQuestion
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
3. If ANY match found: first read `server/shared/version.ts` to get current APP_VERSION, then call the AskUserQuestion tool:

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

4. If user chose "Да": read `server/shared/version.ts`, increment patch (e.g. 1.0.014 → 1.0.015), edit file, append `(v1.0.015)` to commit message
5. Output SHORT commit message (3-5 words, english, prefix: fix/add/update/refactor/remove) as:

```bash
git add -A && git commit -m "message" && git push
```

No text before or after the code block.
