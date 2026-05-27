---
name: dev-restart-rules
description: When to restart dev server vs rely on HMR/watch
type: feedback
---

Frontend changes → HMR подхватит автоматически, перезапуск не нужен.
Backend changes → `--watch` flag в `bun run dev` перезапустит сервер автоматически при изменении .ts файлов.

**Why:** Пользователь не хочет лишних перезапусков. В dev режиме `bun --watch` и Vite HMR обрабатывают изменения автоматически.

**How to apply:** Не предлагать перезапуск `bun run dev:browser` если изменения в .ts файлах — watch подхватит. Перезапуск нужен только при изменении package.json, .env, или конфигов (vite.config, tsconfig).
