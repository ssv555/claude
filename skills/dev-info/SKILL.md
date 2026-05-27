---
name: dev-info
description: Show the developer's guide — all skills, commands, branch rules, workflow on moscow_my. Use when user says "/dev-info", "что я могу", "какие команды", "помощь по dev", "/di".
model: sonnet
allowed-tools: Read(*)
---

# dev-info

Краткая справка разработчику: команды, ветки, workflow.

## Status block

```
SKILL:  dev-info
MODEL:  sonnet
```

## Алгоритм

1. Прочитать `/opt/claude-shared/DEV_GUIDE.md` (прямой путь — `~/.claude/DEV_GUIDE.md` симлинк, но dev из своего шелла туда не зайдёт; через claude CLI можно оба пути).
2. Вывести содержимое **полностью** в чат с короткой шапкой:
   ```
   Гид: /opt/claude-shared/DEV_GUIDE.md (read-only)

   <содержимое файла>
   ```
3. Если файл не найден — сообщить шефу: «`/opt/claude-shared/DEV_GUIDE.md` отсутствует, попроси шефа запустить `/dev bootstrap`».

## Что НЕ делать

- Не модифицировать DEV_GUIDE.md — он root-owned, read-only.
- Не выдумывать команды, не описанные в гиде.
