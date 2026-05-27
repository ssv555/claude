---
name: Never create debug/temp artifacts in project root
description: Playwright screenshots, temp scripts, debug dumps, any throwaway files MUST NOT be created in the project root — use dedicated subfolders or .gitignored locations
type: feedback
originSessionId: 8599fc9c-c1aa-43d5-bf42-f1e041d474f0
---
Мусорные файлы (playwright screenshots, debug dumps, временные скрипты, любые одноразовые артефакты) **никогда** не создаются в корне проекта.

Правильные места (VDole):
- Playwright screenshots → `.tmp/playwright/Images/` (это `--output-dir` в [.mcp.json](.mcp.json), уже в .gitignore через `.tmp/`)
- Прочие Playwright-артефакты (console logs, page snapshots, ручные дампы) → `.playwright-mcp/` (тоже gitignored)
- Временные скрипты → создавать в `.tmp/` и удалять сразу после использования, либо в корне но **с префиксом `tmp_`** и гарантированным удалением в той же последовательности Bash-команд
- Debug-логи → `back/log/` или аналог в .gitignore

**Why:** Корень проекта — это витрина репозитория. Любой мусор там сразу виден в `git status`, попадает в `git add -A`, засоряет историю, бесит ревьюеров. Инциденты: `vk-*.png` (19 Apr), `qa-*.png` 13 штук (22 Apr) — оба раза Playwright MCP положил скриншоты в корень.

**Почему `--output-dir` не спасает:** Playwright MCP применяет `--output-dir` только когда `browser_take_screenshot` вызван **без** явного `filename`. Если передать `filename: "qa-01.png"` — путь резолвится от **cwd** (= корень проекта), игнорируя конфиг. Это поведение MCP-сервера, не настраивается.

**How to apply:**
- В вызове `mcp__playwright__browser_take_screenshot` и `mcp__playwright_iso__browser_take_screenshot` параметр `filename` **всегда** указывать с явным префиксом папки: `filename: ".tmp/playwright/Images/qa-01-auth.png"`. **НЕ** просто `filename: "qa-01-auth.png"`.
- Если filename не нужен читаемый — НЕ передавать параметр вообще, MCP сам положит в `--output-dir` со сгенерированным именем.
- Перед любым коммитом проверять `git status --short` на untracked файлы в корне — если там что-то из моих действий, удалять до `git add`.
- Временные `tmp_*.ts` скрипты — удалять сразу в том же `Bash` вызове где они использовались (`bun ... && rm tmp_*.ts`).
