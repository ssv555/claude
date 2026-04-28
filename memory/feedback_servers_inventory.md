---
name: Servers inventory — never ask user how to connect
description: All user's servers are pre-configured as MCP servers AND in ssh-servers.json. Never ask "how do I connect to X" — find it yourself.
type: feedback
originSessionId: 4a48c027-14ef-4f44-ad95-766e46cde474
---
Все серверы пользователя уже настроены и доступны двумя путями: **MCP-серверы** в `~/.claude/settings.json` (`mcp__<name>__*` enabled) И **SSH-конфиг** в `D:/Data/Documents/Programming/Projects/WEB/.ssh/ssh-servers.json` + `~/.ssh/config`.

**Соглашение по именованию ключей:** `<server>_<user>` — без префиксов `id_`/`id_ed25519_`. Все ключи — ed25519. Для повседневной работы конвенция плоская и единообразная.

**Текущий инвентарь** (на 2026-04-26 — проверять `ssh-servers.json` перед использованием):

| Server | Host | Port | User | Key (relative to D:/.../WEB/) | MCP name |
|---|---|---|---|---|---|
| moscow_my | 195.2.75.212 | 1022 | root | `.ssh/moscow_my_root` | `mcp__moscow_my__*` |
| amsterdam_my | 77.238.231.203 | 1022 | root | `.ssh/amsterdam_my_root` | `mcp__amsterdam_my__*` |
| amsterdam_grey | 94.103.80.11 | 22 | www-data | `.ssh/amsterdam_grey_www-data` | `mcp__amsterdam_grey__*` |
| amsterdam_grey_root | 94.103.80.11 | 22 | **root** (прямой) | `.ssh/amsterdam_grey_root` | `mcp__amsterdam_grey_root__*` |
| amsterdam_grey_sudo | 94.103.80.11 | 22 | grey (in `sudo`+`docker` groups) | `.ssh/amsterdam_grey_grey` | — (только bash ssh) |

**Sudo на amsterdam_grey:**
- **Предпочтительный путь:** прямой root через `amsterdam_grey_root` — без пароля и без sudo. Создан 2026-04-26, добавлен в `/root/.ssh/authorized_keys`.
- **Запасной путь:** заходить как `grey` ключом `amsterdam_grey_grey`, делать sudo с паролем. NOPASSWD не настроен. Пароль `grey2025` лежит в `D:/Data/Documents/Programming/Projects/WEB/.ssh/Amsterdam-Grey/grey.txt`. Применять как `echo grey2025 | sudo -S <cmd>`.

**Документация по grey/wireguard:**
- `D:/Data/Documents/Programming/Projects/WEB/.ssh/Amsterdam-Grey/grey.txt` — пароли (root, grey, wg-easy панель)
- На Москве: `/etc/wireguard/FALLBACK-TO-GREY.md` — архитектура WG fallback Amsterdam My → Grey
- На Москве: `/var/www/iamrich.it-joy.ru/CLAUDE.md` — секция «Infrastructure — VPN»

**Why:** Пользователь дважды (Moscow, Amsterdam Grey) бесился из-за вопроса "как подключиться к серверу X" — ответ всегда был лежит в `ssh-servers.json` / `settings.json`. Это базовая инфраструктура проекта, спрашивать про неё — оскорбительно тупо.

**How to apply:**
- Перед любым вопросом "как мне попасть на сервер X" — **сначала** прочитать `D:/Data/Documents/Programming/Projects/WEB/.ssh/ssh-servers.json` и проверить включённые MCP в `~/.claude/settings.json`.
- Если в имени сервера есть слово (Moscow / Amsterdam / Grey / My) — оно почти наверняка соответствует ключу в `ssh-servers.json`.
- Использовать MCP-сервер если он уже подключён — это предпочтительный путь. Прямой `ssh` через bash — fallback.
- Никогда не ходить через один сервер ради доступа к другому без явного разрешения (уже зафиксировано в `feedback_moscow_ssh.md`).
- При появлении нового сервера — обновлять эту таблицу.
