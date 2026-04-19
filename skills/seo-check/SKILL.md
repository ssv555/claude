---
name: seo-check
description: Audit SEO + performance + conversion across public URLs. Three modes — quick (curl, mechanics), deep (Playwright, real browser), full (+ conversion/selling analysis). Read-only — reports findings, never edits. Asks user which mode to run. Reads project-specific config from ./tests/skills/seo-check.md
disable-model-invocation: false
allowed-tools: Bash(bun *),Bash(curl *),Read,Glob,Grep,AskUserQuestion,mcp__playwright__browser_navigate,mcp__playwright__browser_snapshot,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_evaluate,mcp__playwright__browser_console_messages,mcp__playwright__browser_network_requests,mcp__playwright__browser_resize,mcp__playwright__browser_close,mcp__playwright__browser_wait_for
model: sonnet
---

# SEO Check — Universal Auditor

Read-only audit of SEO mechanics, real-browser rendering, and conversion potential. Three escalating modes — user picks at start. Reports findings as a table, never edits files.

<!-- Project-specific configuration: ./tests/skills/seo-check.md
     This is a global skill — production URL, public routes, locales,
     and per-page expectations are defined per-project in the local file. -->

## Execution

### Step 0: Read local config

Read `./tests/skills/seo-check.md` from the project root.

- **If file exists** — parse the sections described under "Config format" below.
- **If file NOT found** — print the template (see "Config format") and STOP.

### Step 1: Ask user which mode + which environment

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
