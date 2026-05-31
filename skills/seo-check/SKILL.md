---
name: seo-check
description: Audit SEO across two routes — live mode (curl + Playwright on running site, default; quick/deep/full sub-levels) or source mode (`/seo-check text` — only reads the project sources: data files, sitemap, robots, JSON-LD logic). Read-only, reports findings, never edits. Reads project config from ./tests/skills/seo-check.md
argument-hint: "[text]"
disable-model-invocation: false
allowed-tools: Bash(bun *),Bash(curl *),Read,Glob,Grep,AskUserQuestion,mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_evaluate,mcp__playwright__browser_console_messages,mcp__playwright__browser_network_requests,mcp__playwright__browser_resize,mcp__playwright__browser_close,mcp__playwright__browser_wait_for
model: sonnet
---

# SEO Check — Universal Auditor

Read-only audit of SEO mechanics, real-browser rendering, and conversion potential, **or** source-only audit of texts + structure in repo files. Reports findings as a table, never edits.

<!-- Project-specific config: ./tests/skills/seo-check.md (production URL, public routes, locales, per-page expectations). -->

## Arguments — pick the route at invocation

| Invocation | Route | What it does |
|---|---|---|
| `/seo-check` (no arg) | **Live mode** | Curl + Playwright on the running site. Asks user for environment (dev/prod) and sub-level (quick/deep/full). |
| `/seo-check text` / `texts` / `content` / `source` / `src` | **Source mode** | Reads ONLY repo source files: data JSONs, sitemap.xml, robots.txt, head template, build-static logic. No HTTP requests, no browser, no dev-server required. Audits texts (titles/descriptions/CTAs/FAQ/stats) and structure (sitemap/hreflang/JSON-LD coverage). |

Detect by lowercasing the first arg and matching against `text|texts|content|source|src|in-source`. Anything else (or missing) → Live mode.

If you can't determine the arg from the invocation context, default to **Live mode** and proceed with Step 1 below.

## Execution

### Step 0: Read local config (both modes)

Read `./tests/skills/seo-check.md` from the project root.

- **If file exists** — parse the sections described under "Config format" below.
- **If file NOT found** — print the template (see "Config format") and STOP.

### Step 0.5: Source mode (if invoked with `text` arg)

Skip Steps 1–8 entirely. Go to "## Source mode audit" further below.

### Step 1: Ask user which mode + which environment (Live mode only)

Use `AskUserQuestion` with **two** questions in one call:

**Q1: Какое окружение проверить?**

Build options dynamically from the local config's `## Environments` section. Typical options:

| Option | Label | Description |
|--------|-------|-------------|
| 1 | Dev | Стенд разработчика (например vdole-ssv.it-joy.ru). Свежий код, до деплоя. |
| 2 | Prod | Боевой продакшн. Может отставать от dev — проверять перед/после деплоя. |

If only one URL configured — skip this question, use it.

**Q2: Какой уровень аудита запустить?**

| Option | Label | Description |
|--------|-------|-------------|
| 1 | Quick | Только curl. Мета-теги, canonical, hreflang, sitemap, robots, OG/Twitter, JSON-LD. ~30 сек, без браузера. |
| 2 | Deep | Quick + Playwright: рендер после hydration, скриншоты desktop/mobile, битые ссылки, цепочки редиректов, OG-превью, console errors, network failures. ~3 мин. |
| 3 | Full | Deep + конверсионный анализ: value proposition, CTA above the fold, trust signals, читаемость, LCP/CLS/INP, mobile UX, friction в формах. ~5 мин. |

Wait for explicit choices. Use the chosen URL as `{base}` for all subsequent fetches.

### Step 2: Run Quick checks (always)

Print header:

```
**SEO Check — Quick** [0/N]
```

#### A. robots.txt and sitemap.xml

1. **robots.txt** — fetch `{production}{robots.path}`. Verify:
   - HTTP 200
   - References Sitemap directive matching `{sitemap.path}`
   - Contains all entries from `must_disallow`
   - Does NOT accidentally `Disallow: /` for `User-agent: *`

2. **sitemap.xml** — fetch `{production}{sitemap.path}`. Verify:
   - HTTP 200, valid XML
   - Every URL in `## Public URLs` appears in sitemap (for each locale)
   - `<lastmod>` present and not older than 12 months
   - `<loc>` URLs return HTTP 200 (HEAD request, sample up to 20)
   - `hreflang` alternates symmetric

#### B. Per-page checks

For each URL × locale, fetch and verify:

3. **HTTP status** — 200, no redirect chain
4. **Charset** — `<meta charset="UTF-8">`
5. **Lang attribute** — `<html lang="...">` matches locale
6. **Viewport** — `<meta name="viewport" content="width=device-width, initial-scale=1.0">`
7. **Title** — present, 10–60 chars, unique
8. **Description** — present, 50–160 chars, unique
9. **Canonical** — present, absolute, points to self
10. **hreflang** — one tag per locale + `x-default`, symmetric, absolute
11. **Open Graph** — `og:type`, `og:title`, `og:description`, `og:url`, `og:image`, `og:site_name`, `og:locale`
12. **Twitter Card** — `twitter:card` (summary_large_image), `twitter:title`, `twitter:description`, `twitter:image`
13. **Structured data** — JSON-LD if `json_ld_required: true`, validate JSON parses
14. **H1** — exactly one, non-empty
15. **Images alt** — every `<img>` has non-empty `alt` (WARN)
16. **noindex check** — public pages must NOT have `noindex`
17. **OG image** — fetch URL, verify HTTP 200 + `image/*` Content-Type
18. **Yandex verification** (if enabled) — meta tag present on `/`

#### C. Cross-page

19. **Title uniqueness** — no duplicates
20. **Description uniqueness** — no duplicates
21. **Canonical loops** — no canonical points to 404 or non-canonical URL

### Step 3: Run Deep checks (if mode ≥ Deep)

Print header:

```
**SEO Check — Deep** [0/M]
```

For each public URL × locale, use Playwright:

22. **Real browser render** — `browser_navigate` to URL, wait for network idle. Capture `browser_snapshot`. Verify the same SEO elements (title, meta, canonical, JSON-LD) are present **after hydration** — sometimes React strips/replaces head tags.
23. **Console errors** — `browser_console_messages`. Any `error` level → FAIL with message.
24. **Network failures** — `browser_network_requests`. Any 4xx/5xx → FAIL with URL+status.
25. **Broken internal links** — extract all `<a href>` pointing to same origin via `browser_evaluate`, HEAD-request each, report 404s.
26. **Redirect chains** — for every URL in sitemap + every internal link, follow redirects with `curl -sIL`. Report any chain length > 1 or any 302 (should be 301).
27. **Mobile screenshot** — `browser_resize` to 375×812 (iPhone), `browser_take_screenshot`. Save to `.playwright-mcp/seo-{lang}-{slug}-mobile.png`.
28. **Desktop screenshot** — `browser_resize` to 1440×900, `browser_take_screenshot`. Save to `.playwright-mcp/seo-{lang}-{slug}-desktop.png`.
29. **OG preview render** — fetch og:image URL directly, verify dimensions match `og:image:width`/`og:image:height`. Mention as a note: "Соцсети закешируют этот превью — проверить в [opengraph.xyz](https://www.opengraph.xyz/) перед запуском".
30. **Hydration mismatch** — diff curl HTML vs post-hydration HTML for `<head>`. Report any meta/canonical/JSON-LD that disappeared, changed, or got duplicated.

### Step 4: Run Full checks (if mode = Full)

Print header:

```
**SEO Check — Full (Selling)** [0/K]
```

For each public URL × locale (use Playwright snapshot from Step 3):

31. **Value proposition clarity** — extract H1 + first paragraph + first CTA. Assess: does a first-time visitor understand in 5 seconds *what this is, who it's for, what action to take*? Report as PASS/WARN with reasoning. Reference: lands well-known frameworks (StoryBrand, "5-second test").
32. **CTA above the fold** — at 1440×900 viewport, capture screenshot of viewport-only (not full page). Verify at least one prominent CTA (`<button>`, `<a class*="btn">`, or visually prominent link) is visible without scrolling. List all CTAs found above the fold with their text.
33. **Trust signals** — scan page for: testimonials, customer logos, security badges (SSL, GDPR, certifications), team/contact info, social proof (user count, ratings). Report what's present and what's missing.
34. **Friction in forms** — if page has `<form>`, count fields. >5 fields = WARN (high friction). Required fields without clear labels = WARN. No inline validation hints = note.
35. **Readability** — word count, average sentence length (< 20 words = good), passive voice ratio (< 20% = good). Flag walls of text without subheadings/bullets.
36. **Performance metrics** — `browser_evaluate` to read `performance.getEntriesByType('navigation')[0]` and `PerformanceObserver` for LCP/CLS/INP. Report numbers. Targets: LCP < 2.5s, CLS < 0.1, INP < 200ms.
37. **Mobile UX** — at 375×812: tap targets < 44px → WARN (Apple HIG). Horizontal scroll → FAIL. Text smaller than 16px on body → WARN.
38. **Heading hierarchy** — extract all `<h1>`–`<h6>` order. Skipped levels (h1 → h3) = WARN. Multiple h1 = FAIL (already in Quick).
39. **Internal linking depth** — for each public URL, count clicks from homepage. Pages > 3 clicks deep = WARN (poor SEO juice flow).
40. **Page weight** — total transferred bytes from `browser_network_requests`. > 2 MB on mobile = WARN. > 5 MB = FAIL.

### Step 5: Output during execution

For each check, print as it runs:

```
[i/N] Check Name -- checking...
[i/N] Check Name -- PASS
[i/N] Check Name -- FAIL: <one-line reason, with URL>
[i/N] Check Name -- WARN: <one-line reason>
```

**Run ALL checks** even if earlier ones fail.

### Step 6: Summary

```
## SEO Audit Summary — {mode}

### FAIL (must fix)
| # | Check | URL | Issue |

### WARN (should review)
| # | Check | URL | Issue |

### PASS
N checks passed

### Screenshots (Deep+ only)
- [seo-ru-home-desktop.png](.playwright-mcp/seo-ru-home-desktop.png)
- ...

### Selling notes (Full only)
{prose summary of conversion findings — what works, what doesn't, top 3 recommendations}
```

### Step 7: Verdict

- All PASS → "SEO в порядке"
- Any FAIL → "Найдены критичные проблемы — нужно править"
- Only WARN → "Критики нет, есть что улучшить"

Plus for Full mode: 1–3 sentence summary of "что мешает продавать сильнее".

### Step 8: Offer fix flow

If any FAIL or WARN was found, ask via `AskUserQuestion`:

> Найдено: {N_fail} критичных, {N_warn} предупреждений. Запустить /seo-fix?

Options:

| Option | Label | Description |
|--------|-------|-------------|
| 1 | Да, всё (механика авто + контент по очереди) | полный проход |
| 2 | Только механические (быстро, без вопросов) | canonical, hreflang, robots, sitemap, OG-картинка размер |
| 3 | Только конкретные пункты | пользователь укажет номера в следующем сообщении |
| 4 | Нет, я сам | завершить |

**Do NOT auto-invoke** `/seo-fix` — wait for user choice. If 1/2/3, instruct user to run `/seo-fix` next (the fix skill will pick up findings from this conversation context).

If all PASS — skip Step 8 entirely.

## Source mode audit (`/seo-check text`)

Triggered when invoked with first arg matching `text|texts|content|source|src|in-source`. **No HTTP, no Playwright, no dev-server.** Reads only repo source files — for content revision / structure audit before deploy.

### Files audited

| Группа | Файл (от project root) | Что проверяем |
|---|---|---|
| Тексты лендингов | `front/src/static/data/ru.json` + `front/src/static/data/en.json` | title/description длины, og:* parity, CTA-копи, stats-плейсхолдеры, FAQ полнота, contact email/url consistency, RU↔EN parity ключей |
| Sitemap | `front/public/sitemap.xml` | XML валидность, completeness vs PAGES в build-static, hreflang симметричность, домен совпадает с canonical, lastmod не устарел (>12 мес) |
| Robots | `front/public/robots.txt` | Allow/Disallow полнота, Sitemap-директива указывает на правильный URL, нет случайного `Disallow: /` для `User-agent: *` |
| Head template | `front/src/static/partials/_head.eta` | Наличие canonical/hreflang/og:*/twitter:*/JSON-LD/yandex-verification, использование dynamic `it.data.site.url` (не hardcoded), `og:image` ссылка валидна |
| Build pipeline | `front/scripts/build-static.ts` | JSON-LD `@graph` — Organization/WebSite на всех, FAQPage на landing, WebPage на остальных; PAGES массив vs sitemap.xml; BreadcrumbList/Product/Offer — WARN если отсутствуют |
| SPA shell | `front/app.html` | canonical/hreflang/og:*/twitter:* для SPA-роута (если admin-area индексируется хотя бы под `noindex`) |

If any of these paths don't exist in this project — emit a WARN with a note about which file is missing and continue with what's available.

### Checks (Source mode)

Print header:

```
**SEO Check — Source** [0/N]
```

For each project source file:

**Texts (per locale, per page):**

S1. **title length 10–60 chars** — иначе FAIL with actual length
S2. **description length 50–160 chars** — иначе FAIL
S3. **og_title present and ≤ 95 chars** — иначе WARN
S4. **og_description present and ≤ 200 chars** — иначе WARN
S5. **Title uniqueness across pages × locales** — дубли = FAIL
S6. **Description uniqueness** — дубли = WARN
S7. **CTA in `landing.cta.button`** — non-empty, contains action verb (regex: `^(Начать|Зарегистр|Создать|Купить|Найти|Получить|Start|Sign|Get|Create|Find|Buy)`) → иначе WARN
S8. **Stats placeholders** (`landing.stats.*`) — если значения круглые числа типа `120+`, `300+`, `10 000+`, `4,8 млрд` — WARN «выглядит как маркетинговый placeholder, проверь правдивость»
S9. **FAQ count ≥ 5** — иначе WARN (мало для FAQPage schema)
S10. **`site.email` matches `site.url` host** — `info@vdole.pro` для `https://vdole.pro` ✓; mismatch = FAIL
S11. **No dead-domain references** — grep по text values на `vdole.it-joy.ru` и других упразднённых хостах (из local config или CLAUDE.md `## Domain Terminology` если упомянуты)
S12. **RU ↔ EN key parity** — каждый ключ в `ru.json` должен быть в `en.json` и наоборот. Missing keys = FAIL (поломает рендер EN-страницы)
S13. **`legal.last_updated_date`** — если дата старше 12 мес от сегодня → WARN

**Structure (sitemap + robots + head + build-static):**

S14. **sitemap.xml — valid XML** (try parse, FAIL on error)
S15. **Every page from build-static.ts `PAGES` array (excluding error_404/error_403/docs) appears in sitemap** for both RU and EN locales
S16. **Sitemap URLs use canonical host** matching `site.url` из ru.json. Mismatch = FAIL
S17. **hreflang в sitemap симметричны** — каждый URL имеет ru/en/x-default, alt-URL ведут на реально существующие записи в том же sitemap
S18. **lastmod не старше 12 месяцев** (от текущей даты) — WARN если устарел
S19. **robots.txt — Sitemap-директива** указывает на тот же URL что и реальный файл, домен корректный
S20. **robots.txt — Allow** покрывает все public URL из local config
S21. **robots.txt — Disallow** содержит все из `must_disallow` local config + нет случайного `Disallow: /` для `User-agent: *`
S22. **_head.eta — обязательные теги** — наличие в шаблоне: title, description, canonical, hreflang × 3, og:type/title/description/url/image/site_name/locale, twitter:card/title/description/image, JSON-LD inject, yandex-verification (если `yandex_verification: true` в config)
S23. **_head.eta — нет hardcoded URL** — все URL через `<%= it.data.site.url %>...`, не литералы. Hardcoded `https://vdole.pro/...` или подобное в шаблоне = WARN
S24. **build-static.ts — JSON-LD coverage** — Organization + WebSite в `@graph` для всех страниц (S24a), FAQPage на landing (S24b), WebPage на не-landing (S24c)
S25. **build-static.ts — BreadcrumbList** — отсутствует = WARN (рекомендация для будущих per-business pages)
S26. **build-static.ts — Product/Offer** — отсутствует = WARN если в проекте есть страницы офферов (по `## Public URLs` в config)
S27. **PAGES в build-static.ts vs sitemap.xml — расхождения** — список страниц в build генерится, но не попадает в sitemap (или наоборот) = FAIL
S28. **SPA shell (front/app.html)** — если файл существует, содержит yandex-verification, canonical, og:*, JSON-LD (Organization + WebSite). Расхождение с _head.eta по токенам = WARN

### Output (Source mode)

Use the same format as Live mode:

```
[i/N] Check Name -- PASS
[i/N] Check Name -- FAIL: <reason, with file:line if applicable>
[i/N] Check Name -- WARN: <reason>
```

Print summary table identical to Step 6, then Step 7 verdict, then offer `/seo-fix` if any FAIL/WARN (Step 8 logic) — `/seo-fix` уже работает по исходникам, ровно тот же контекст.

### Why two modes

- **Live mode** ловит то, что не видно из исходников: hydration React, console errors, network failures, OG-preview через Playwright. Нужен **запущенный сервер** (prod или dev).
- **Source mode** ловит косяки лучше проверяемые в репо: тексты, неполный sitemap, отсутствующие meta-теги в шаблоне, дубли titles, RU/EN parity, schema.org gaps. **Не требует сервера.**

Оба используют один local config (`./tests/skills/seo-check.md`); Live проверяет рендеренный HTML, Source — исходники.

## Implementation notes

- **Quick mode**: `curl -sS -L -A "Mozilla/5.0 (compatible; SEOAudit/1.0)" -o /tmp/seo-page.html -w "%{http_code}" {url}` for HTML. `curl -sSI -o /dev/null -w "%{http_code}" {url}` for HEAD.
- **Deep/Full mode**: use Playwright MCP. Always `browser_close` at end.
- Parse HTML with bun + regex (don't pull cheerio — inline regex for `<title>`, `<meta>`, `<link>`, `<h1>`, `<html lang>` is enough).
- Network calls retry 3× with 2s backoff (global rule for external integrations).
- Screenshots → `.playwright-mcp/` (gitignored). Use slugified filename: `seo-{lang}-{path-slug}-{viewport}.png`.
- For SPA: if a public route relies on JS rendering for SEO content (Quick HTML has empty `<title>` or no meta), flag as **CRITICAL FAIL** in Quick mode regardless.

## Config format

Local file `./tests/skills/seo-check.md`:

```markdown
# SEO Check — {ProjectName}

## Environments
- prod: https://example.com
- dev: https://example-dev.com
  (at least one required; both recommended — user picks at runtime)

## Site
- locales: ru, en
- default_locale: ru
- locale_url_pattern: /{lang} prefix for non-default

## Public URLs
- /
- /about
- /pricing

## Sitemap
- path: /sitemap.xml

## Robots
- path: /robots.txt
- must_disallow: /api/, /auth/

## Meta expectations
- og_image: /img/og_default.png (1200x630)
- json_ld_required: true
- yandex_verification: true

## Selling expectations
(used by Full mode — what each landing should sell)
- /: главная — продаёт идею платформы инвесторам и предпринимателям
- /welcome_agents: продаёт регистрацию предпринимателям
- /welcome_contragents: продаёт регистрацию инвесторам

## Skip checks
(optional — list check numbers + reason)
- 15 (images alt) — landing has decorative SVGs only

## On success
SEO в порядке

## On failure
Найдены критичные проблемы
```

## Rules

- **Read-only.** Never edit any file. Report only.
- **Dev by default.** Audit dev stand by default — это место, где код в процессе работы. Prod аудитят отдельно после деплоя для финальной верификации. Если в конфиге только prod — используем его.
- **Communicate in Russian.**
- **Don't fix anything** — fixes are a separate task.
- **Always ask which mode** — never assume.
- **Always close browser** at end of Deep/Full runs (`browser_close`).
