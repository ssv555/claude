---
name: Anti-DPI proxy для домашнего PC (Hiddify + VLESS+REALITY через moscow_my)
description: Текущий рабочий канал для Anthropic/AI/YouTube/etc. с домашнего Windows-PC. TUN-режим Hiddify v4 → VLESS+Reality на moscow_my:443 (SNI=vk.com) → wg0 → Amsterdam exit. Split-tunnel по Region:ru.
type: reference
---

## Архитектура (2026-05-22 — актуально)

```
Windows PC (Hiddify v4.1.1, Service mode: VPN = TUN)
  └── routing внутри Hiddify: Region:ru — geoip:ru direct, остальное → proxy outbound `claude-pc-moscow § 0`
        └── VLESS+REALITY+Vision, uTLS chrome, SNI=vk.com
              → moscow_my :443 TCP
                  → nginx stream SNI-routes vk.com → 127.0.0.1:38760
                      → Xray inbound-38760 → freedom-wg outbound
                          → wg0 kernel routing: AS399358 → amsterdam_grey, остальное → amsterdam_my
```

Никаких SSH-туннелей, NSSM-сервисов, nginx LB на Windows. Один Hiddify-клиент.

## Где документация / source of truth

**Сервер + клиент полностью:** [`INFRA/servers/moscow_my/docs/vless_reality_claude.md`](D:/Data/Backup/Ubuntu-Servers/INFRA/servers/moscow_my/docs/vless_reality_claude.md) — единый канонический документ. Содержит: цепочку, server-side (inbound-38760 в x-ui.db, nginx stream map, routing rules), client-side (Hiddify настройки, профиль, anti-DPI стек), как получить UUID/keys, snapshot до изменений, эталонные latency, как добавить fallback exit-ноду.

## Ключевые факты для Claude (для быстрого контекста)

- **Клиент**: Hiddify v4.1.1, установлен `C:\Program Files\Hiddify\`, user data в `~/AppData/Roaming/hiddify/hiddify/`.
- **Профиль**: `claude-pc-moscow` (импорт VLESS-URI). Outbound tag в финальном sing-box config: **`claude-pc-moscow § 0`** — это имя для custom route-rules, если они когда-то нужны (через Profile → Config Editor: tree).
- **Region:ru** в Hiddify Settings → Routing делает split-tunnel автоматически: `geoip:ru`+`geosite:category-ru` → direct, остальное → proxy. **Custom per-domain rules не нужны** для базового сценария.
- **Anti-DPI стек**: REALITY (dest=vk.com:443) + Vision (XTLS) + uTLS chrome + TLS fragment + mixed SNI case + padding + DoH (1.1.1.1) + IPv6 off.
- **Серверный inbound**: id=3, tag=`inbound-38760`, listen `127.0.0.1:38760`, в `/etc/x-ui/x-ui.db`. UUID/PublicKey/ShortIds получить через `sudo sqlite3 /etc/x-ui/x-ui.db "SELECT settings, stream_settings FROM inbounds WHERE tag='inbound-38760';"`.
- **nginx stream**: `/etc/nginx/stream.conf` map уже содержит `vk.com → 127.0.0.1:38760` рядом с `www.microsoft.com → :38756` и `www.bing.com → :38758`.
- **HTTPS_PROXY env**: НЕ нужен. TUN перехватывает на уровне адаптера, env переменные были бы лишним слоем.
- **Эталонные latency** (замер 2026-05-22): vk.com 65мс (direct), api.anthropic.com 320–540мс (через NL exit), ifconfig.me → `77.238.231.203` (amsterdam_my).

## Что заменило / удалено

Старая схема (4 NSSM-сервиса на Windows + nginx LB + 3 SSH-туннеля → tinyproxy на Amsterdam) — снесена до 2026-05-19. Снимок-инвентарь старой схемы временно лежит в `~/.claude/tmp/proxy_old_inventory.md` (на ~неделю, потом удалить).

## Фаза 2 — реализована 2026-05-22

В Hiddify создан Авто-профиль с sing-box `urltest` outbound, объединяющий 3 узла: moscow-vk (основной), amsterdam_grey direct, amsterdam_my direct. Существующие VLESS-inbound-ы на серверах переиспользованы — поднимать ничего не пришлось. Все профили в Hiddify переименованы по схеме «PC → откуда → куда → SNI → назначение».

Текущий tolerance=50ms даёт побочный эффект балансировки (узлы «одинаково лучшие», urltest колеблется). Для классического main+fallback — поднять до 200-300ms.

Детали (структура Авто-профиля, таблица tolerance↔поведение, как менять, рекомендации) — в [vless_reality_claude.md](D:/Data/Backup/Ubuntu-Servers/INFRA/servers/moscow_my/docs/vless_reality_claude.md) → раздел «Fallback exit-ноды (Фаза 2)».
