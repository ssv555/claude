# Global Memory

## Feedback
- [.mcp.json disabled servers](feedback_mcp_servers_off.md) — never flag mcpServers-off in reviews
- [Hyperlinks in docs](feedback_hyperlinks_in_docs.md) — all external service mentions must be hyperlinks, not plain text
- [Playwright — tabs, not multiple servers](feedback_playwright_tabs.md) — for parallel browser work use `browser_tabs action=new` in the single live MCP server, never duplicate `@playwright/mcp` entries
- [Settings relative paths](feedback_settings_relative_paths.md) — additionalDirectories: only `../`, `~/`, `./` — never absolute with usernames
- [Task checkbox format](feedback_todo_checkbox_format.md) — [x]/[ ] at START of line, never mid/end; no tables for status
- [No git stash](feedback_no_git_stash.md) — Never use git stash with parallel sessions; use WIP commits; never stash drop without user confirmation
- [Servers inventory](feedback_servers_inventory.md) — All servers (moscow_my / amsterdam_my / amsterdam_grey / amsterdam_grey_root) pre-configured as MCP + ssh-servers.json — find it, never ask
- [Brevity is default](feedback_brevity_default.md) — Default = shortest answer that's actionable; long form only on explicit "распиши/подробно"
- [User instruction FIRST](feedback_user_action_first.md) — Ручной юзер-шаг → инструкция первой строкой, мои доки/код параллельно
- [Vivaldi personal browser](feedback_vivaldi_personal_browser.md) — `playwright_vivaldi` MCP цепляется к живой сессии Vivaldi юзера; per-task разрешение, не закрываю ничего, не трогаю закладки

## Reference
- [MTProto proxy infra](../docs/mtproto-proxy.md) — Moscow-front + Amsterdam grey/my architecture, configs, diagnostics, rollback. Set up 2026-04-26.
- [Proxy tunnels](reference_proxy_tunnels.md) — HTTP proxy localhost:8080 via SSH tunnels to Amsterdam tinyproxy, NSSM services auto-start
- [antifilter.network BGP](reference_antifilter_bgp.md) — public BGP peer with RKN registry prefixes for router policy routing
- [.ps1 ASCII-only](feedback_windows_script_encoding.md) — Write saves no-BOM, PS 5.x mangles Cyrillic → use English in PowerShell scripts
