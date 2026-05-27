---
name: Deprecated paths — always full-project sweep
description: When fixing any deprecated/renamed URL path, do a single project-wide grep for ALL legacy variants in one shot — not the file the bug surfaced in
type: feedback
originSessionId: 4e5a3213-4b27-41a5-9434-0ba215f08654
---
При любом ренейме URL/пути (`/app/agent/*` → `/app/business-owner/*`, `/welcome_agents` → `/welcome_business`, `/app/contragent/*` → `/app/investor/*`, `/welcome_contragents` → `/welcome_investors`, и любых будущих) — НЕ чинить только тот файл, где баг всплыл. Сразу делать ОДИН grep по всему проекту по всем легаси-вариантам (regex alternation) и чинить ВСЕ найденные вхождения в одной итерации.

**Why:** User уже несколько раз ловит остатки `/app/agent/*` и `/welcome_agents` в коде, лендингах, sitemap, robots, tests, lighthouse, диаграммах. Каждый раз я чиню «точку обращения» и пропускаю остальное. Это раздражает: «ты это уже исправлял МНОГО РАЗ и каждый раз опять находишь — что за безалаберность». Полная зачистка дешевле, чем 5 итераций по одному файлу.

**How to apply:**
1. При первом упоминании deprecated пути в задаче → запустить grep по корню проекта по всем вариантам сразу:
   ```
   Grep pattern="/app/agent|/app/contragent|/welcome_agents|/welcome_contragents" path=<project_root>
   ```
2. Категоризировать находки:
   - **Active code/assets** (front, back outside redirect handlers, public/, tests, scripts, configs) → ЧИНИТЬ.
   - **Backend 301-редиректы** в `back/src/app.ts` (.get("/app/agent/...", () => Response.redirect(...))) → ОСТАВЛЯТЬ (это и есть фича для legacy URL).
   - **Описание редиректов** в `CLAUDE.md`, `docs/GLOSSARY.md`, `docs/tech/DESIGN_SYSTEM.md` (упоминание факта существования 301) → ОСТАВЛЯТЬ (документация о редиректах должна упоминать legacy URL).
   - **Archive** (`docs/archive/**`) → НЕ ТРОГАТЬ (правило проекта).
   - **`_original.svg` / `_backup*` etc.** → НЕ ТРОГАТЬ (бэкапы по соглашению).
3. Чинить всё в одной серии Edit-ов, без перепрыгивания между файлами.
4. Финальный grep по тому же паттерну — подтвердить что осталось только то, что должно остаться (301 handlers + docs + archive).
5. `bun run typecheck` для уверенности что ссылки на TanStack routes (`useParams({ from: '...' })`) и пр. не сломались.

**Конкретные вхождения этого ренейма** (зафиксировано 2026-05-14, могут добавиться новые — всё равно grep делать заново):
- front: `app.html`, `public/sitemap.xml`, `public/robots.txt`, `public/diagrams/platform_overview.svg`, `src/business-owner/**`, `src/components/landing/**`
- tests: `tests/e2e/business-owner-i8.spec.ts`, `snap-initial.yml`
- configs: `lighthouserc.cjs`, `tests/skills/seo-check.md`, `tests/skills/pre-deploy-check.md`
- docs (active): `docs/SEO.md`, `docs/diagrams/platform_structure.drawio`
