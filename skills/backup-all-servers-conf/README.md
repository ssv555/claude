# /backup-all-servers-conf

Полный config-snapshot всех personal-infra серверов: nginx, LE certs (с private keys), WireGuard/AmneziaWG keys, Xray privateKey, wg-easy admin pass, systemd units, cron расписания, custom scripts, sysctl, fail2ban, sshd hardening и т.п.

**Self-contained bash-script**: orchestration + SSH + tar + scp + sha256 indexing + drift detection + manifest generation в одном файле. Claude управляет только запуском и пересказом summary — содержимое snapshot'ов не читает (правило в SKILL.md).

## Usage

```bash
# Все 4 сервера
bash ~/.claude/skills/backup-all-servers-conf/backup-all-servers-conf.sh

# Один сервер по alias
bash ~/.claude/skills/backup-all-servers-conf/backup-all-servers-conf.sh moscow_my

# Кастомный INFRA root
INFRA_ROOT=/some/path bash ~/.claude/skills/backup-all-servers-conf/backup-all-servers-conf.sh
```

Default `INFRA_ROOT=/d/Data/Backup/Ubuntu-Servers/INFRA`. Все snapshot'ы кладутся в `$INFRA_ROOT/servers/<alias>/snapshots/<DATE>_full-config/`.

## Что делает (по шагам)

1. **Pack previous snapshots** — все `*_full-config/` папки старше сегодняшней пакуются в `<DATE>_full-config.tar.gz` на уровне `snapshots/`, исходные папки удаляются. Event-marker snapshots (`*_post-xray`, `*_post-fulltunnel`) не трогаются.
2. **Remote probe + tar** — на сервере: `ss`, `iptables-save`, `systemctl`, `docker ps`, `versions`, `df`, `ip a`, плюс `tar czh` всего configs-дерева.
3. **scp bundle** на локальную машину.
4. **Extract** в `<DATE>_full-config/configs/` + `state/`.
5. **Index** — `find . -type f` → `sha256sum + size + mtime + path` → `state/files-index.txt`.
6. **Drift detection** — извлекает `files-index.txt` из самого свежего предыдущего snapshot'а (папки или `.tar.gz`), diff → `+N new, -M removed, ~K changed`.
7. **Manifest stub** — генерируется `manifest.md` если ещё не существует (ручные нюансы не перезаписываются).
8. **Cleanup remote** — `/tmp/snap-*` на сервере удаляется.

## Требования к окружению

### SSH config aliases (`~/.ssh/config`)

Скрипт использует alias'ы вместо `user@host:port`. Каждый сервер должен быть прописан в `~/.ssh/config`:

```
Host amsterdam_grey_ssv
    HostName 94.103.80.11
    Port 53847
    User ssv
    IdentityFile "D:/.../amsterdam_grey/keys-client/ssv/id_ed25519"
```

Проверка: `ssh <alias> 'echo OK'` должно работать БЕЗ ввода пароля/passphrase.

### Sudo на сервере

Удалённый пользователь должен иметь **sudo nopasswd** (т.к. чтение `/etc/letsencrypt/`, `/etc/amnezia/`, и т.п. требует root). Проверка: `ssh <alias> 'sudo -n true && echo sudo-OK'`.

### Git Bash / WSL

Скрипт на bash. Запускается из Git Bash, WSL, или любого *nix shell. Использует стандартные unix-утилиты: `tar`, `ssh`, `scp`, `find`, `sha256sum`, `comm`, `join`, `awk`.

## Server registry

Жёстко прописан в начале скрипта:

```bash
SERVERS=(
  "amsterdam_grey|amsterdam_grey_ssv"
  "moscow_my|moscow_my"
  "amsterdam_my|amsterdam_my"
  "vdole_pro_timeweb_moscow|vdole_pro_timeweb_moscow"
)
```

Формат: `alias|ssh_host_alias`. Первое поле — имя папки в `INFRA/servers/`, второе — alias из ssh config.

### Per-server paths

`PATHS_<alias>` — whitespace-separated список путей для `tar`. Например:

```bash
PATHS_amsterdam_grey="/etc/nginx /etc/iptables /etc/netplan /etc/cron.d /etc/letsencrypt ... /usr/local/etc/xray"
```

При добавлении нового тулинга на сервер (например, новый сервис с конфигом в `/etc/foo/`) — допиши путь в соответствующую `PATHS_*` строку.

### Common excludes

`COMMON_EXCLUDES` — паттерны исключаемые на ВСЕХ серверах: `/etc/letsencrypt/csr`, `/etc/nginx/_backup_*`, `*.bak.*`, большие бинарники (`bun`, `mtg`, `prometheus*`).

## Output структура

```
INFRA/servers/<alias>/snapshots/
├── 2026-05-21_full-config/             ← сегодняшний (развёрнут)
│   ├── manifest.md                     ← авто-stub + ручные нюансы
│   ├── configs/                        ← полное дерево config-файлов
│   │   ├── etc/
│   │   ├── root/                       ← где применимо (wg-easy state и т.п.)
│   │   └── usr/local/                  ← где применимо (custom scripts)
│   ├── configs.tar.gz                  ← bundled
│   └── state/
│       ├── ports.txt, iptables.txt, ip6tables.txt
│       ├── services.txt, docker.txt
│       ├── versions.txt, os.txt, disk.txt
│       └── files-index.txt             ← sha256+size+mtime+path
├── 2026-05-20_full-config.tar.gz       ← старые — одиночные архивы
├── 2026-05-19_full-config.tar.gz
└── ...
```

Event-marker snapshots (`2026-05-20_post-xray/`, и т.п.) хранятся параллельно и не управляются скриптом.

## Storage

- Per-server snapshot: ~1–3 MB (в развёрнутом виде), ~0.1–0.5 MB (в .tar.gz).
- Все 4 сервера: ~7 MB развёрнутыми, ~1.5 MB как архивы.
- При daily backup: за месяц ~7 MB (только текущий day) + 30 × ~1.5 MB ≈ **50 MB/месяц**.

Storage держится экономно благодаря packing — развёрнутая только сегодняшняя папка.

## Troubleshooting

### `Permission denied (publickey)`

SSH alias не настроен или ключ недоступен. Проверь:
```bash
ssh -v <alias>   # увидеть какой ключ пытается использовать
```
Если ключ есть, но не работает — проверь права (`chmod 600 ~/.ssh/id_*`) и `IdentityFile` путь в config.

### `sudo: a password is required`

На сервере у пользователя нет sudo nopasswd. Добавь:
```bash
ssh <alias>
sudo visudo
# Добавь: <user> ALL=(ALL) NOPASSWD: ALL
```

### `tar: ... time stamp ... is N s in the future`

Несущественно — clock skew между сервером и локальной машиной (десятые доли секунды). Можно игнорировать или синхронизировать NTP.

### `scp: Connection closed`

Обычно следствие SSH auth failure. См. выше.

### Запустил два раза в один день — что было?

Безопасно: внутри одного дня `<DATE>_full-config/` **перезаписывается** (configs/, state/, configs.tar.gz, files-index.txt — все заменяются). Manifest.md сохраняется. Старые snapshot'ы остаются.

### Скрипт показал `0` drift но что-то изменилось

Diff делается по path + sha256. Если файл переименован — будет `-1 removed, +1 new`. Если содержимое менялось — `~1 changed`. Файлы с тем же hash и тем же path = 0 drift.

### Хочу посмотреть что внутри старого .tar.gz архива

```bash
tar tzf 2026-05-20_full-config.tar.gz | less
tar xzf 2026-05-20_full-config.tar.gz -C /tmp/restore-test/
```

## Restore

```bash
cd snapshots/2026-05-21_full-config
cd configs
sudo cp -a etc /
sudo cp -a root /     # где есть
sudo cp -a usr /      # где есть
sudo systemctl daemon-reload
sudo systemctl restart nginx postgresql@18-main xray   # + relevant
sudo certbot certificates    # проверить LE валидным
sudo iptables-restore < ../state/iptables.txt    # если netfilter-persistent
```

## Связано

- [SKILL.md](SKILL.md) — инструкции для Claude (правила, allowed-tools, workflow)
- [INFRA/SNAPSHOTS-INDEX.md](../../../../../Data/Backup/Ubuntu-Servers/INFRA/SNAPSHOTS-INDEX.md) — мастер-индекс snapshot'ов
- [feedback_skill_placement.md](../../memory/feedback_skill_placement.md) — почему этот skill глобальный, а не project-local

## История

- **2026-05-21** — создан skill после ручного создания первого full-config snapshot всех 4 серверов через MCP SSH. Skill переносит этот workflow в self-contained bash script. Протестирован на amsterdam_grey: 363 файла, 1.1 MB, ~54 секунды; packing старого snapshot и drift detection работают.
