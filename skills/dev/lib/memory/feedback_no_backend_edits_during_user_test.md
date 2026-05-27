---
name: No backend edits while user is mid-test
description: VDole backend HMR invalidates the user's vd_session cookie (serverStart in token). Any back/src/** edit during the user's test cycle logs them out.
type: feedback
originSessionId: 4e5a3213-4b27-41a5-9434-0ba215f08654
---
В VDole `vd_session` cookie включает `serverStart` от backend; **любое** изменение файла в `back/src/**` триггерит HMR-рестарт → новый `serverStart` → cookie протухает → /api/init 401 → AppGate показывает форму авторизации. Это by design (фича безопасности), но в dev-цикле это означает: пока юзер залогинен и тестирует — backend трогать НЕЛЬЗЯ.

**Why:** Сценарий 2026-05-14. Юзер тестировал wizard «Добавить бизнес». Я фиксил `back/src/lib/business-validation.ts` (рестарт #1) — юзер переавторизовался. Затем я бампнул `back/src/shared/version.ts` (правило: после правок locales) — рестарт #2 → cookie снова стухла → юзер опять на /auth, не сделав теста. Юзер: «Я ВООБЩЕТО ПЕРЕАВТОРИЗОВАЛСЯ ПЕРЕД ТЕСТОМ И СТРАНИЦУ ОБНОВИЛ!!!»

**How to apply:**
1. **Группировать backend-изменения в ОДИН batch** до того как юзер начал тестовый цикл. Все правки `back/src/**` — за один заход, до первого «попробуй».
2. **APP_VERSION-bump — последний шаг сессии**, не в середине. После правок `front/public/locales/**` правило требует поднять версию — но это можно отложить до момента «всё работает, коммитим». Делать bump в середине = провоцировать logout.
3. **Если в середине теста выявлен баг в `back/`** — предупредить юзера: «правлю backend, после фикса нужно переавторизоваться». Без предупреждения — выглядит как косяк без причины.
4. **Frontend HMR — безопасен**, cookie не страдает. `front/**`, `front/public/locales/**` можно править свободно.
5. **Что считается `back/src/**` для этого правила:** ВСЁ внутри `back/src/` — `routes/`, `lib/`, `db/`, `middleware/`, `shared/`, `bot_*/`. Даже `shared/version.ts` (как ни странно) триггерит рестарт.
