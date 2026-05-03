---
name: Local proxy tunnels (Amsterdam) — full infrastructure
description: Complete proxy infrastructure: Windows NSSM services, SSH tunnels to Amsterdam/Moscow servers, tinyproxy on remote, nginx LB on local. HTTP proxy at localhost:8080.
type: reference
---

## Proxy Infrastructure — Full Picture

### Серверы

| Сервер | IP | SSH port | Роль в прокси | Что крутится |
|---|---|---|---|---|
| **amsterdam_grey** | 94.103.80.11 | SSH 1022 | Primary proxy | tinyproxy на порту 8888 |
| **amsterdam_my** | 77.238.231.203 | SSH 1022 | Backup proxy | tinyproxy на порту 8888 |
| **moscow_my** | 195.2.75.212 | SSH 1022 | Jump-host для backup #2 | nginx stream (MTProxy router) + SSH jump |

### Локальная машина Windows (PC пользователя)

**Итоговая точка входа: `http://127.0.0.1:8080`** — HTTP-прокси через Амстердам.

#### Схема трафика

```
Приложение (браузер, Claude Code, curl)
  → localhost:8080 (nginx stream load balancer)
    → localhost:8081 → SSH → amsterdam_grey:8888 (tinyproxy)   [PRIMARY]
    → localhost:8082 → SSH → amsterdam_my:8888 (tinyproxy)     [BACKUP #1]
    → localhost:8083 → SSH → moscow_my → amsterdam_my:8888     [BACKUP #2, ProxyJump]
```

#### Windows-сервисы (NSSM)

**ОС:** Windows 11 Pro. Сервисы зарегистрированы через [NSSM](https://nssm.cc/) (Non-Sucking Service Manager) — обёртка, превращающая любой .exe в Windows-сервис с автоперезапуском.

**Расположение NSSM:** `C:\Users\ssv55\scoop\apps\nssm\current\nssm.exe` (установлен через scoop)

**Все 4 сервиса:**
- Запуск: `AUTO_START` (стартуют при загрузке Windows)
- Учётка: `LocalSystem`
- При падении: NSSM перезапускает автоматически
- Display name prefix: `Claude Proxy: <name>`

| Service name | Display name | Тип | Local port | Что запускает |
|---|---|---|---|---|
| `claude-tunnel-grey` | Claude Proxy: claude-tunnel-grey | SSH tunnel | 8081 | `ssh -N -L 8081:localhost:8888 amsterdam_grey_root` |
| `claude-tunnel-my` | Claude Proxy: claude-tunnel-my | SSH tunnel | 8082 | `ssh -N -L 8082:localhost:8888 amsterdam_my` |
| `claude-tunnel-moscow` | Claude Proxy: claude-tunnel-moscow | SSH tunnel | 8083 | `ssh -N -J moscow_my -L 8083:localhost:8888 amsterdam_my` |
| `claude-proxy-router` | Claude Proxy: claude-proxy-router | nginx LB | 8080 | `nginx -p "C:\Users\ssv55\.claude-proxy" -c nginx.conf -g "daemon off;"` |

**SSH binary:** `C:\Program Files\Git\usr\bin\ssh.exe` (Git for Windows)

**SSH-опции** (одинаковые на всех туннелях):
- `-N` — без интерактивного шелла, только туннель
- `StrictHostKeyChecking=accept-new`
- `ServerAliveInterval=10` — keepalive каждые 10с
- `ServerAliveCountMax=3` — 3 пропуска = разрыв (NSSM перезапустит)
- `ExitOnForwardFailure=yes` — если порт занят, не висеть молча
- `BatchMode=yes` — никогда не спрашивать пароль

**nginx** запущен с `daemon off;` — NSSM сам управляет процессом, не нужен daemon mode.

#### Конфиги и пути

| Что | Путь |
|---|---|
| nginx конфиг | `C:\Users\ssv55\.claude-proxy\nginx.conf` |
| nginx логи | `C:\Users\ssv55\.claude-proxy\logs\access.log`, `error.log` |
| nginx binary | `C:\Users\ssv55\scoop\apps\nginx\current\nginx.exe` |
| NSSM binary | `C:\Users\ssv55\scoop\apps\nssm\current\nssm.exe` |
| SSH config | `C:\Users\ssv55\.ssh\config` (алиасы: amsterdam_grey_root, amsterdam_my, moscow_my) |
| SSH ключи | `D:\Data\Documents\Programming\Projects\WEB\.ssh\` |

#### Failover логика (nginx upstream)

- Primary: 8081 (amsterdam_grey) — `max_fails=2 fail_timeout=10s`
- Backup #1: 8082 (amsterdam_my) — backup
- Backup #2: 8083 (amsterdam_my via Moscow) — backup
- `proxy_connect_timeout 5s`, `proxy_timeout 10m`, `proxy_next_upstream on`

### Использование

| Контекст | Настройка |
|---|---|
| Браузер (Vivaldi/Chrome) | `--proxy-server="http://127.0.0.1:8080"` |
| Переменная среды | `HTTPS_PROXY=http://127.0.0.1:8080` |
| curl | `curl -x http://127.0.0.1:8080 https://example.com` |
| Claude Code | переменная `HTTPS_PROXY` в env |
| Любое приложение | HTTP proxy `127.0.0.1:8080` |

### Браузеры — настройка прокси (TODO, не завершено)

**Задача:** запускать Vivaldi и Яндекс Браузер через прокси Амстердам.

**Пути к .exe:**
- Vivaldi: `C:\Users\ssv55\AppData\Local\Vivaldi\Application\vivaldi.exe`
- Яндекс: `C:\Users\ssv55\AppData\Local\Yandex\YandexBrowser\Application\browser.exe`

**Способ:** ярлык с флагом `--proxy-server="http://127.0.0.1:8080"`

**Статус:**
- Прокси работает (проверено: `curl -x http://127.0.0.1:8080 https://ifconfig.me` → 94.103.80.11)
- Vivaldi — не проверено
- Яндекс — не работает с флагом `--proxy-server`, причина не выяснена. Вернуться к диагностике.

### Управление сервисами

```cmd
:: Статус всех
sc query claude-tunnel-grey
sc query claude-tunnel-my
sc query claude-tunnel-moscow
sc query claude-proxy-router

:: Перезапуск (через NSSM — корректно убивает дочерний процесс)
nssm restart claude-tunnel-grey
nssm restart claude-tunnel-my
nssm restart claude-tunnel-moscow
nssm restart claude-proxy-router

:: Остановка / запуск
nssm stop claude-tunnel-grey
nssm start claude-tunnel-grey

:: Посмотреть параметры сервиса
nssm get claude-tunnel-grey Application
nssm get claude-tunnel-grey AppParameters

:: Редактировать сервис (GUI)
nssm edit claude-tunnel-grey

:: Удалить сервис
nssm remove claude-tunnel-grey confirm

:: Создать новый сервис (пример)
nssm install claude-tunnel-new "C:\Program Files\Git\usr\bin\ssh.exe"
nssm set claude-tunnel-new AppParameters "-N -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -o BatchMode=yes -L 8084:localhost:8888 <host>"
nssm set claude-tunnel-new DisplayName "Claude Proxy: claude-tunnel-new"
nssm set claude-tunnel-new Start SERVICE_AUTO_START
nssm start claude-tunnel-new
```

```bash
# Логи nginx
cat "C:\Users\ssv55\.claude-proxy\logs\access.log"
cat "C:\Users\ssv55\.claude-proxy\logs\error.log"

# Проверка что прокси работает
curl -x http://127.0.0.1:8080 https://ifconfig.me
```
