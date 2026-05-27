---
name: VDole has project-local .tmp/ folder — use it for session temp files
description: Временные файлы текущей сессии класть в VDole/.tmp/, не в ~/.claude/tmp/ и не в корень проекта
type: feedback
originSessionId: 723eccaf-facc-4820-9fe6-7d52a670a92d
---
В проекте VDole есть папка `.tmp/` в корне (gitignored) — туда складываются все временные сессионные артефакты: дампы БД, SQL, диффы, чаты-полотенца, плейрайт-скриншоты и т.п. Уже используется активно (vdole_data_*.sql, columns.diff, plans/, playwright/, chat-validator/).

**Why:** пользователь явно настроил `.tmp/` именно для этого; класть временные файлы в `~/.claude/tmp/` (глобальный Claude-каталог) — засорение глобального пространства проектным мусором. Память `feedback_no_root_artifacts.md` запрещает корень проекта, но `.tmp/` — это и есть legitimate проектная temp-папка.

**How to apply:** любой временный файл по запросу «временный файл / temp / на сессию» → `d:/Data/Documents/Programming/Projects/WEB/VDole/.tmp/<name>`. НЕ `~/.claude/tmp/`, НЕ корень проекта, НЕ `.docs/`.

Исключение: глобальные кросс-проектные temp (для нескольких проектов сразу) — тогда `~/.claude/tmp/` ОК.
