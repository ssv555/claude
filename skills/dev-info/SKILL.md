---
name: dev-info
description: Show the developer's guide — all skills, commands, branch rules, daily workflow on moscow_my. Use when user says "/dev-info", "что я могу", "какие команды", "помощь по dev", "/di".
model: sonnet
allowed-tools: Read(*), Bash(*)
---

# dev-info

Краткая справка разработчику: команды, ветки, workflow.

## Status block

```
SKILL:  dev-info
MODEL:  sonnet
```

## Алгоритм

1. **Прочитать гид:** `/opt/claude-shared/DEV_GUIDE.md` (прямой путь — `~/.claude/DEV_GUIDE.md` симлинк, но dev из своего шелла туда не зайдёт; через claude CLI оба пути работают).

2. **Прочитать RULES.md:** `/opt/claude-shared/RULES.md` — обязательные правила, версионируются (SHA-256). Покажи короткую шапку: текущий хеш + статус принятия (есть ли флаг приёма у этого пользователя для текущего хеша).

3. **Вывести содержимое DEV_GUIDE.md полностью** в чат с шапкой:
   ```
   Гид: /opt/claude-shared/DEV_GUIDE.md (read-only)
   Правила: /opt/claude-shared/RULES.md  (read-only)  status: <accepted ✓ / NOT ACCEPTED ⚠>

   <содержимое DEV_GUIDE.md>
   ```

4. **Хвост:** одна строка о статусе приёма правил:
   ```bash
   HASH=$(sha256sum /opt/claude-shared/RULES.md | awk '{print $1}')
   FLAG="/opt/claude-shared/rules_acceptances/${USER}__${HASH}.flag"
   [ -r "$FLAG" ] && echo "rules: ✓ accepted" || echo "rules: ⚠ NOT ACCEPTED — re-login to accept"
   ```

5. Если файлы не найдены — сообщить шефу: «`/opt/claude-shared/DEV_GUIDE.md` (или RULES.md) отсутствует, попроси шефа запустить `/dev bootstrap`».

## Что НЕ делать

- Не модифицировать DEV_GUIDE.md / RULES.md — они root-owned read-only.
- Не выдумывать команды, не описанные в гиде.
