---
name: Use internal platform infrastructure, never push work to user
description: Before proposing external input (URL, copy-paste, manual export), check the project for existing internal infra (CAS, attachments, auth, etc.) and USE it — users of a platform expect it to be self-contained
type: feedback
originSessionId: a1e637be-cac6-4938-a9bd-f1320351e258
---
Когда бизнес-задача требует загрузки/хранения/обработки файла (аватар, документы, видео, фото бизнеса, КП, фин.модель), категорически **запрещено**:

- Просить пользователя ввести **внешний URL** на файл («загрузите куда-то и вставьте ссылку»).
- Предлагать **внешнее хранилище** (Google Drive, Dropbox, imgur), если в проекте есть своё.
- Оставлять **ручной копипаст** как MVP-решение «до тех пор пока не сделаем нормально».

**Why:** платформа VDole позиционируется как **самодостаточное** решение для партнёров и инвесторов. Любое «сгоняй на сторонний сервис» = говно редкостное (дословно от пользователя 24.04). Мы сами — платформа, если что-то не реализовано у нас, надо **реализовать** а не пуш к пользователю. Плюс: внешние URL несут tracker-риск для приватности, могут протухнуть, блокируются CSP, не соответствуют 152-ФЗ (ПДн на сторонних хостах).

**How to apply:**

1. **Перед кодом проверяй инфраструктуру проекта:**
   - Файлы (картинки, PDF, документы) → [`back/src/lib/attachment-service.ts`](back/src/lib/attachment-service.ts) (CAS с SHA-256 дедупликацией, см. [ATTACHMENTS_CAS.md](docs/tech/ATTACHMENTS_CAS.md)). Текущий `entity_type` = только `expense`, но архитектурно рассчитан на расширение — добавь `entity_type` для своей сущности.
   - Крипто (ключи, шифрование) → [`back/src/lib/crypto-aes-gcm.ts`](back/src/lib/crypto-aes-gcm.ts).
   - Сессии / auth → `authMiddleware`, `csrfHeaders()`.
   - Видео/картинки public-facing → attachments + WebP-конвертер.
2. **Если инфра есть — используй.** Даже если надо расширить (добавить новый entity_type в enum, добавить новый route) — расширяй, не сворачивай в URL.
3. **Если инфры реально нет** (редкий случай) — **сначала обсуди** с пользователем, планировать ли создание. Не делай затычку без явного согласия.
4. **При ревью архитектурного плана / BA-отчёта — особенно внимательно** смотри на поля `avatar_url`, `logo_url`, `video_url`, `document_url`, `cover_url`, `file_url` и им подобные. URL-поля в бизнес-сущностях = красный флаг. Либо это CAS-id (тогда переименовать в `*_attachment_id`), либо это дефект.

**Прецедент:** в I8 (2026-04-23) я (BA + Developer) принял avatar как URL-input, оправдавшись тем что «attachments pipeline жёстко привязан к expense». Правильное решение было — расширить attachments на `entity_type='agent_profile'` (одна строка в enum + миграция в seed.ts). Пользователь 24.04 разнёс это как «говно редкостное», и был прав. Ошибка стоила одной итерации pipeline.

**Дополнительные зоны риска в VDole:**

- Аватар агента ([`agent_profiles.avatar_url`](back/src/db/schema/agent-profiles.ts)) — должно быть через attachments-CAS.
- Документы бизнеса (Устав, аренда, паспорт) — attachments + `entity_type='business'`. (Task 05 с полиморфными documents — Post-MVP улучшение; на MVP расширение attachments — норма.)
- Офферы (task 06): фото/видео бизнеса, КП, фин.модель — через attachments.
- Avatars контрагентов (task 04) — то же самое.
- QR-коды офферов (task 06) — генерируются у нас, не ссылки на внешние генераторы.
