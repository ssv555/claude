---
name: backup-all-servers-conf
description: Config snapshot of all personal infra servers (moscow_my, amsterdam_my, amsterdam_grey, vdole_pro) via self-contained bash script; Claude orchestrates and reports only. Use when user says "забэкапь все сервера", "обнови бэкапы серверов", "/backup-all-servers-conf".
model: haiku
allowed-tools: Bash(bash *), Bash(*backup-all-servers-conf.sh*), Read(~/.claude/skills/backup-all-servers-conf/*)
---

# backup-all-servers-conf

Скрипт делает ВСЁ end-to-end — ты только запускаешь и пересказываешь summary пользователю.

## Status block

В начале выполнения распечатать:

```
SKILL:  backup-all-servers-conf
MODEL:  haiku
```

## Что делает скрипт (НЕ ТРОГАТЬ файлы вручную)

Для каждого сервера:
1. **Pack previous snapshots** — все старые папки `*_full-config/` (кроме сегодняшней) целиком пакуются в единый `<DATE>_full-config.tar.gz` на уровне `snapshots/`, исходные папки удаляются. Так держим только один развёрнутый snapshot — текущий, остальные — компактные одиночные архивы.
2. SSH-probe — собирает state (ports, iptables, services, docker, versions, OS, disk)
3. На сервере: `tar czh` с include-paths (включая секреты) → bundle в `/tmp/`
4. `scp` бандла локально
5. Распаковка в `$INFRA_ROOT/servers/<alias>/snapshots/<DATE>_full-config/`
6. Генерация `files-index.txt` (sha256 + size + mtime + path) — для drift-detection
7. Diff с предыдущим snapshot → `+N new, -M removed, ~K changed`
8. **Генерация `manifest.md` stub'а** (только если файл не существует) — авто-метаданные + drift summary + top dirs. Server-specific нюансы дописываются вручную поверх.
9. Cleanup `/tmp/` на сервере

**Storage logic:** только текущий день расspak'ан полностью, прошлые дни — только `configs.tar.gz` (≈10× компактнее). Event-marker snapshots (`*_post-xray`, `*_post-fulltunnel` и т.п.) НЕ трогаются — pattern строго `*_full-config/`.

**Серверы и их include-paths** жёстко прописаны в скрипте (config-блок в начале файла). При добавлении/изменении путей — править скрипт.

## Как запускать

```bash
# Все сервера:
bash ~/.claude/skills/backup-all-servers-conf/backup-all-servers-conf.sh

# Один сервер по alias:
bash ~/.claude/skills/backup-all-servers-conf/backup-all-servers-conf.sh amsterdam_grey

# Кастомный INFRA root:
INFRA_ROOT=/some/path bash ~/.claude/skills/backup-all-servers-conf/backup-all-servers-conf.sh
```

Default INFRA root: `/d/Data/Backup/Ubuntu-Servers/INFRA`.

## КРИТИЧЕСКИЕ ПРАВИЛА

1. **НЕ читать содержимое snapshot-файлов.** Запрещено `cat`, `Read`, `grep` любых файлов внутри `$INFRA_ROOT/servers/<alias>/snapshots/`. Это секреты (privateKeys, PSK, LE archive, passwords). Скрипт сам с ними работает, ты их не видишь.
2. **НЕ редактировать configs вручную.** Если что-то нужно изменить — править исходники на сервере и перезапустить скрипт.
3. **НЕ распаковывать tar.gz сам в чате.** Распаковкой занимается скрипт.
4. Допускается читать ТОЛЬКО:
   - `state/files-index.txt` (метаданные: hash/size/mtime/path — не контент)
   - `state/*.txt` (ports, services, versions, etc — не секреты)
   - `manifest.md` (документация snapshot'а)
   - стандартный stdout скрипта (drift summary)

## Workflow

1. Запустить скрипт через `Bash` (без аргументов = все 4 сервера, ~30-60 сек на сервер).
2. Прочитать stdout — там drift report по каждому серверу.
3. Пересказать пользователю в формате:
   ```
   Server          | Files | Drift vs prev
   amsterdam_grey  |   364 | +0 -0 ~0   (no changes)
   moscow_my       |   628 | +2 -1 ~5
   amsterdam_my    |   462 | +0 -0 ~3   (mostly LE renewal)
   vdole_pro       |   366 | +1 -0 ~2
   ```
4. Если есть drift — упомянуть, что нужен `svn commit` через TortoiseSVN.
5. Если сервер failed — назвать какой и предложить запустить только его: `bash backup-all-servers-conf.sh <alias>`.

## Что НЕ делать

- Не ходить в snapshot папки и не листать их (`ls -la $INFRA_ROOT/servers/...`).
- Не показывать содержимое files-index.txt построчно (только агрегаты).
- Не предлагать «откатиться к старому snapshot» в ответ на drift — это нормально, бэкап для того и есть.
- Не запускать скрипт автоматически — только по явному запросу пользователя или его `/backup-all-servers-conf`.

## Когда расширять список серверов / путей

Если пользователь:
- добавил новый сервер → попросить alias/user@host/port + список путей → дописать в `SERVERS` + `PATHS_<alias>` в скрипте
- изменил пути на существующем → попросить точный список → обновить `PATHS_<alias>`

Любая правка скрипта — через Edit с показом diff'а пользователю.
