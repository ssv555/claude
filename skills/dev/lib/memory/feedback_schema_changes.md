---
name: Schema changes — MVP default is clean drop+recreate, no ALTER
description: At MVP stage, schema changes (add/rename/remove columns/tables/enums) go via clean drop + db:push. ALTER forbidden. Don't ask — apply default.
type: feedback
originSessionId: 5394acb7-72c0-4ef7-a739-11ec2270b2ac
---
При любых изменениях schema (добавление, удаление, переименование колонок/таблиц/enum-ов) на MVP-стадии: дефолт = clean recreate. ALTER не предлагать ни в каком виде. **Перед `bun run db:push`** дать пользователю полный список объектов для DROP — он дропает сам. После его дропа `db:push` сгенерирует только `CREATE` без ALTER.

**Why:** Инцидент 2026-05-05 — рефакторинг agent→business_owner / contragent→investor. Я последовательно предлагал interactive-rename через db:push с ALTER, потом ALTER-функцию в seeds.ts по образцу `migrateLegacyDevRole`, потом `DROP SCHEMA public CASCADE` через `bun -e`, потом psql. Все варианты — нарушение правила «`db:push` handles schema, NEVER standalone migrations». Пользователь раз за разом капсом писал «ALTER не должно быть, всё как в первый раз на стадии MVP». Спрашивать «ALTER vs clean» больше не нужно — всегда clean.

**How to apply:**
- Грепнуть все таблицы и enum-ы, которые затронуты изменением (включая таблицы с переименованными колонками — их тоже дропать).
- Дать пользователю полный SQL-блок `DROP TABLE IF EXISTS … CASCADE; DROP TYPE IF EXISTS …;` со всеми затронутыми объектами.
- НЕ предлагать ALTER, ALTER-в-seeds, DROP SCHEMA через bun -e, psql DROP DATABASE — ни в каком виде.
- После дропа пользователем — `bun run db:push` сгенерирует только CREATE.
- Этот дефолт изменится при выходе на prod — тогда пересмотреть правило.
