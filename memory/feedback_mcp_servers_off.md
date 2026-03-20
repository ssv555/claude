---
name: MCP servers disabled in .mcp.json is intentional
description: User intentionally moves MCP servers to mcpServers-off to save tokens — never flag this in code reviews
type: feedback
---

`.mcp.json` с серверами в `mcpServers-off` — это намеренная практика пользователя для экономии токенов. MCP-серверы часто не нужны и тратят токены впустую.

**Why:** Пользователь уже неоднократно объяснял это. Повторные вопросы раздражают.

**How to apply:** При code review НЕ упоминать `.mcp.json` с отключёнными серверами как замечание или рекомендацию. Считать это нормальным состоянием файла.
