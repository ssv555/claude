---
name: Naming without ambiguity (prepositions matter)
description: In script/command/function names always use explicit prepositions (to/from/with) to kill ambiguity about direction or subject
type: feedback
originSessionId: ce7ebbc5-47a5-47c8-b490-c0e2a2520843
---
В именах скриптов, команд, функций не должно быть двусмыслицы по направлению действия. Явно писать предлоги `to` / `from` / `with`.

**Bad:** `push-prod` — куда-то пушит prod? или пушит на prod? непонятно.
**Good:** `push-to-prod` / `pull-from-prod` / `sync-with-prod`.

**Bad:** `copy-users`, `sync-data`.
**Good:** `copy-users-to-backup`, `sync-data-from-source`.

**Why:** пользователь явно назвал предыдущее именование «дебильным» — первое название ничем не говорит о направлении. Двусмысленное имя заставляет читателя гадать или лезть в код.

**How to apply:** при предложении любого имени (скрипта, команды в package.json, функции, CLI-флага) проверять: понятно ли из названия ЧТО и КУДА/ОТКУДА? Если глагол подразумевает направление (push, pull, copy, sync, move, import, export) — обязательно добавлять предлог и объект. Не ждать, пока пользователь переименует руками.
