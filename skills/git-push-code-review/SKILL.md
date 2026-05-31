---
name: git-push-code-review
description: Generate git command for add + commit + push with code review
disable-model-invocation: false
allowed-tools: Bash(git *), Read, Edit, Write, Glob, AskUserQuestion, Agent(code-reviewer), ToolSearch, WebFetch
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
3. Try to read `.claude/version-check.json` from the project root (project-specific cached paths and version info):

```json
{
  "cachedPaths": ["front/public/locales/", "back/src/shared/constants.ts"],
  "versionFile": "back/src/shared/version.ts",
  "prodVersionUrl": "https://example.com/api/version"
}
```

If the file does not exist — skip steps 4–5, go directly to step 6.

4. Check if any changed file matches any path from `cachedPaths` array.
5. If ANY match found:
   a. Read the file at `versionFile` path to get current APP_VERSION
   b. Fetch production version: first run `ToolSearch` with query `select:WebFetch` to load the tool schema, then call `WebFetch` with URL from `prodVersionUrl` and prompt `extract version`. Extract `version` field from JSON response. If fetch fails or times out — use `"недоступен"`
   c. **Compare local vs prod version.** Parse both as dot-separated integers (e.g. `0.0.004` → `[0, 0, 4]`). If local > prod (any segment higher, left-to-right) — the bump is ALREADY done, cached files will be re-fetched by clients anyway. **Skip the question entirely, do NOT edit version file, go directly to step 6.** Only ask the user if local == prod, or if prod version is `"недоступен"` (can't compare safely).
   d. Call the AskUserQuestion tool:

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

   e. If user chose "Да": read the `versionFile`, increment patch (e.g. 1.0.014 → 1.0.015), edit file, append `(v1.0.015)` to commit message
6. Check if `.claude/skills/session-archive/SKILL.md` exists in the project root (use Glob). If it exists:

   **Skip condition**: If there was no meaningful dialog in this session — i.e., the conversation contains only skill/command invocations (like `/git-push`, `/version-up`, etc.) without any real discussion, code changes, debugging, or decision-making — skip the archive prompt silently and go to step 7. There is nothing worth archiving when no actual work happened.

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

   - **Да**: Read `.claude/skills/session-archive/SKILL.md` and follow its instructions to create the archive file. After the file is created, continue to step 7.
   - **Пропустить**: Continue to step 7.
   - **Отмена**: Stop immediately. Output nothing. Exit the skill.

   If `.claude/skills/session-archive/SKILL.md` does not exist — skip this step silently.

7. Output SHORT commit message (3-5 words, english, prefix: fix/add/update/refactor/remove) as:

```bash
git add -A && git commit -m "message" && git pull --rebase && git push
```

No text before or after the code block.
