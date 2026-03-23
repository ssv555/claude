---
name: git-push
description: Generate git command for add + commit + push
disable-model-invocation: false
allowed-tools: Bash(git *), Read, Edit, Write, Glob, AskUserQuestion, ToolSearch, WebFetch
model: sonnet
---

Generate a `git add -A && git commit -m "msg" && git pull --rebase && git push` command.

<!-- pull --rebase added for safe parallel work: when multiple developers push to the same branch,
     rebase pulls remote changes before push. For solo work it's a no-op (nothing to rebase). -->

## Execution

1. Run `git status` and `git diff`
2. Try to read `.claude/version-check.json` from the project root. This file defines project-specific cached paths and version info:

```json
{
  "cachedPaths": ["front/public/locales/", "back/src/shared/constants.ts"],
  "versionFile": "back/src/shared/version.ts",
  "prodVersionUrl": "https://example.com/api/version"
}
```

If the file does not exist — skip steps 3–4, go directly to step 5.

3. Check if any changed file matches any path from `cachedPaths` array.
4. If ANY match found:
   a. Read the file at `versionFile` path to get current APP_VERSION
   b. Fetch production version: first run `ToolSearch` with query `select:WebFetch` to load the tool schema, then call `WebFetch` with URL from `prodVersionUrl` and prompt `extract version`. Extract `version` field from JSON response. If fetch fails or times out — use `"недоступен"`
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

   d. If user chose "Да": read the `versionFile`, increment patch (e.g. 1.0.014 → 1.0.015), edit file, append `(v1.0.015)` to commit message
5. Check if `.claude/skills/session-archive/SKILL.md` exists in the project root (use Glob). If it exists:

   **Skip condition**: If there was no meaningful dialog in this session — i.e., the conversation contains only skill/command invocations (like `/git-push`, `/version-up`, etc.) without any real discussion, code changes, debugging, or decision-making — skip the archive prompt silently and go to step 6. There is nothing worth archiving when no actual work happened.

   Otherwise, call AskUserQuestion:
   ```json
   {
     "questions": [{
       "question": "Архивировать сессию перед коммитом?",
       "header": "Archive",
       "options": [
         {"label": "Да", "description": "Создать архив сессии в docs/archive/"},
         {"label": "Пропустить", "description": "Продолжить без архивации"},
         {"label": "Отмена", "description": "Прервать git-push полностью"}
       ],
       "multiSelect": false
     }]
   }
   ```

   - **Да**: Read `.claude/skills/session-archive/SKILL.md` and follow its instructions to create the archive file. After the file is created, continue to step 6.
   - **Пропустить**: Continue to step 6.
   - **Отмена**: Stop immediately. Output nothing. Exit the skill.

   If `.claude/skills/session-archive/SKILL.md` does not exist — skip this step silently.

6. Output SHORT commit message (3-5 words, english, prefix: fix/add/update/refactor/remove) as:

```bash
git add -A && git commit -m "message" && git pull --rebase && git push
```

No text before or after the code block.
