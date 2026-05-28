---
**Архивировано:** 2026-05-28
**Статус:** инфраструктура полностью снесена. Причина: нестабильное соединение, частые обрывы, провалы передачи изображений/эмодзи.
**Сервера:** moscow_my (nginx SNI route), amsterdam_my (telemt+mtproxymax), amsterdam_grey (docker mtproxymax-telemt) — везде удалено.
**Секреты redacted.** См. подробности в [_PC_SSH_TUNNEL_PROXY_REMOVED архив](../../../../D/Data/Backup/Ubuntu-Servers/INFRA/archive/2026-05_pc_ssh_tunnel_proxy_removed.md).
---

# MTProto Proxy — Moscow-front + Amsterdam (grey primary, my overflow)

Telegram MTProto-прокси для обхода ограничений мобильных операторов РФ.
Создано 2026-04-26.

## Зачем эта схема

Мобильные операторы (Мегафон в первую очередь) **режут нестандартные порты**
к иностранным IP, даже если внутри идёт TLS. MTProto-прокси на Amsterdam:8443
работает с домашнего Wi-Fi, но не работает с GSM.

**Решение:** Russia-fronting. Клиент идёт на Moscow:443 (русский IP, стандартный
HTTPS-порт — никто это не блокирует), nginx на Москве по SNI роутит трафик:
- `SNI = cloudflare.com` → mtg на Amsterdam (через два прыжка)
- `SNI = любой_сайт.it-joy.ru` → локальный nginx-http-блок (сайты как обычно)

## Топология

```
Phone (RU/Megafon) → Moscow nginx :443 (TCP) → SNI peek →
  ├── SNI=cloudflare.com (MTProto)
  │        → 127.0.0.1:11443 (no PROXY proto fwd) 
  │        → upstream pool:
  │              primary: 94.103.80.11:8443 (grey, до max_conns=2000)
  │              backup:  77.238.231.203:8443 (my, overflow/failover)
  │        → mtg → Telegram DCs
  │
  └── SNI=что-то-ещё (сайты)
           → 127.0.0.1:11444 (PROXY proto on)
           → 127.0.0.1:8444 (nginx http блоки сайтов, читают real-IP из PP)

Phone HTTP/3 (UDP/443) → отдельная ветка, бьёт прямо в `listen 443 quic` сайтов.
```

## Серверы и роли

| Сервер | IP | Роль |
|---|---|---|
| **moscow_my** | 195.2.75.212 | Frontend: nginx stream :443 SNI-роутер. Точка входа клиентов. |
| **amsterdam_grey** | 94.103.80.11 | mtg primary. 2-ядерный, силён. Крутит mtg + WireGuard. |
| **amsterdam_my** | 77.238.231.203 | mtg backup/overflow. 1-ядерный, слабее. Использует только при перегрузе grey. |

## Telegram-ссылка для клиентов

```
tg://proxy?server=195.2.75.212&port=443&secret=<REDACTED-secret-removed-2026-05-28>
https://t.me/proxy?server=195.2.75.212&port=443&secret=<REDACTED-secret-removed-2026-05-28>
```

Секрет одинаковый на grey и my (FakeTLS под `cloudflare.com`).
Hex: `<REDACTED-hex-removed-2026-05-28>`

## Конфигурация

### Amsterdam (grey + my): mtg

- Установлен: `mtg 2.2.8` в `/usr/local/bin/mtg`
- User: `mtg` (system, no shell, no home)
- Конфиг: `/etc/mtg/config.toml`
- Systemd unit: `/etc/systemd/system/mtg.service` (enabled, auto-start)
- Слушает на `0.0.0.0:8443`
- Логи: `journalctl -u mtg -f`
- Stats endpoint (только grey, локально): `127.0.0.1:3128/stats`

### Amsterdam: firewall (8443 только с Moscow)

**ams_my (UFW):**
```
ufw allow from 195.2.75.212 to any port 8443 proto tcp comment "MTProto from Moscow only"
```

**ams_grey (raw iptables, persisted):**
```
iptables -N MTG_FILTER
iptables -A MTG_FILTER -s 195.2.75.212 -j ACCEPT
iptables -A MTG_FILTER -j DROP
iptables -I INPUT 1 -p tcp --dport 8443 -j MTG_FILTER
iptables-save > /etc/iptables/rules.v4   # iptables-persistent
```

### Moscow: nginx stream-роутер

**Файл:** `/etc/nginx/stream.conf` (включён в `nginx.conf` через top-level `stream { include ... }` блок)

```nginx
map $ssl_preread_server_name $route_target {
    cloudflare.com      127.0.0.1:11443;
    www.cloudflare.com  127.0.0.1:11443;
    default             127.0.0.1:11444;
}

upstream mtproto_pool {
    # grey — primary до 2000 коннектов; my — overflow/failover
    server 94.103.80.11:8443 max_conns=2000 max_fails=3 fail_timeout=30s;
    server 77.238.231.203:8443 backup max_fails=3 fail_timeout=30s;
}

# Фронт :443 — снимает SNI, генерирует PP с реальным client IP в upstream
server {
    listen 443;
    ssl_preread on;
    proxy_pass $route_target;
    proxy_protocol on;
    access_log /var/log/nginx/stream-443.log proxy_443;
}

# MTProto path — читает PP, форвардит RAW (mtg PP не понимает)
server {
    listen 127.0.0.1:11443 proxy_protocol;
    set_real_ip_from 127.0.0.1;
    proxy_pass mtproto_pool;
}

# Sites path — читает PP с фронта, форвардит PP в http :8444
server {
    listen 127.0.0.1:11444 proxy_protocol;
    set_real_ip_from 127.0.0.1;
    proxy_pass 127.0.0.1:8444;
    proxy_protocol on;
}
```

### Moscow: сайты переехали с :443 на :127.0.0.1:8444

Все 8 site-конфигов в `/etc/nginx/conf.d/*.conf`:
```
listen 127.0.0.1:8444 ssl proxy_protocol;
```

Глобально в `nginx.conf` http-блоке:
```
set_real_ip_from 127.0.0.1;
real_ip_header proxy_protocol;
```

HTTP/3 (`listen 443 quic`) **не трогался** — UDP идёт мимо stream-блока,
HTTP/3-клиенты бьют сайтам напрямую.

## Изменение нагрузочного капасити

Поднять/опустить порог переключения на my — одна правка:
```bash
ssh root@moscow 'sed -i "s/max_conns=2000/max_conns=NEW_VAL/" /etc/nginx/stream.conf && nginx -s reload'
```

Текущая `max_conns=2000` поставлена консервативно (mtg на 2-ядерном grey
реалистично тянет 3000-5000 коннектов на ядро без напряга, но grey также
крутит WireGuard).

## Проверка / диагностика

```bash
# Кто получает сейчас MTProto-трафик
ssh root@moscow 'tail -f /var/log/nginx/stream-443.log | grep cloudflare'

# Сводка распределения за последние записи
ssh root@moscow 'awk "/cloudflare\.com/ {print \$3}" /var/log/nginx/stream-443.log | sort | uniq -c | sort -rn'

# Активные TCP-коннекты к mtg на каждом Amsterdam
ssh root@grey 'ss -tn state established sport = :8443 | wc -l'
ssh root@my   'ss -tn state established sport = :8443 | wc -l'

# Mtg stats (grey, локально)
ssh root@grey 'curl -s http://127.0.0.1:3128/stats | jq'

# Логи mtg
ssh root@grey 'journalctl -u mtg -f'

# TLS-handshake-тест: должен ответить cert CN=cloudflare.com (через mtg)
echo Q | openssl s_client -connect 195.2.75.212:443 -servername cloudflare.com -brief

# Тот же тест с обычным SNI: должен ответить cert CN=<sitename>
echo Q | openssl s_client -connect 195.2.75.212:443 -servername it-joy.ru -brief
```

## Откат

Бэкапы конфигов на Москве: `/etc/nginx.bak-2026-04-26_20-02-37`. Для отката:
```bash
ssh root@moscow 'systemctl stop nginx && rm -rf /etc/nginx && cp -a /etc/nginx.bak-2026-04-26_20-02-37 /etc/nginx && systemctl start nginx'
```

Mtg на Amsterdam отключить:
```bash
ssh root@grey 'systemctl stop mtg && systemctl disable mtg'
ssh root@my   'systemctl stop mtg && systemctl disable mtg'
```

## Известные ограничения

**Звонки и видеозвонки в Telegram не работают через прокси** — это by design
у Telegram-клиента. Прокси несёт только MTProto (TCP: чаты, медиа, sync).
Голос/видео идут отдельным UDP-каналом к voice-relay серверам Telegram,
клиент не использует прокси для этого. Лечится только полным VPN
(WireGuard) — тогда UDP заворачивается на сетевом уровне до того как
Telegram-клиент отправляет пакет.

**Real-load CPU балансировка не реализована.** Сейчас балансировка через
`max_conns` (по числу коннектов как proxy для CPU). При масштабе >1000
активных коннектов или появлении конкурирующих сервисов на grey стоит
рассмотреть HAProxy + agent-check для real-time CPU-aware распределения.

## Связанные документы

- `~/.claude/memory/feedback_servers_inventory.md` — все SSH-доступы к серверам
- На Москве `/etc/wireguard/FALLBACK-TO-GREY.md` — WG-fallback архитектура
  (не связано напрямую, но соседняя инфраструктура grey↔my)
