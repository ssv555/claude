---
name: seo-check
description: Audit on-page SEO across public URLs (meta tags, canonical, hreflang, OG/Twitter, JSON-LD, sitemap, robots). Read-only — reports findings, never edits. Reads project-specific config from ./tests/skills/seo-check.md
disable-model-invocation: false
allowed-tools: Bash(bun *),Bash(curl *),Read,Glob,Grep
model: sonnet
---

# SEO Check — Universal Auditor

Read-only SEO audit. Fetches live public URLs, parses HTML, validates against standard on-page SEO checklist. Reports findings as a table — never edits files.

<!-- Project-specific configuration: ./tests/skills/seo-check.md
     This is a global skill — production URL, public routes, locales,
     and per-page expectations are defined per-project in the local file. -->

## Execution

### Step 1: Read local config

Read `./tests/skills/seo-check.md` from the project root.

- **If file exists** — parse the sections described under "Config format" below. Then go to Step 2.
- **If file NOT found** — print:

```
⚠️ Файл ./tests/skills/seo-check.md не найден.

Создайте файл с описанием SEO-конфигурации проекта.
Минимальный шаблон:

## Site
- production: https://example.com
- locales: ru, en
- default_locale: ru
- locale_url_pattern: /{lang} prefix for non-default (например /en/...)

## Public URLs
- /
- /about

## Sitemap
- path: /sitemap.xml

## Robots
- path: /robots.txt
- must_disallow: /api/, /auth/

## Meta expectations
- og_image: /img/og_default.png (1200x630)
- json_ld_required: true
- yandex_verification: true
```

Then STOP. Do not run anything.

### Step 2: Run checks

Print header:

```
**SEO Check** [0/N]
```

Run checks in this order. Each check has its own progress line.

#### Check group A — robots.txt and sitemap.xml

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
   - `hreflang` alternates symmetric (each language references all others + x-default)

#### Check group B — per-page checks

For each URL in `## Public URLs`, for each locale, fetch the page and verify:

3. **HTTP status** — 200 (not 3xx redirect chain, not 4xx/5xx)
4. **Charset** — `<meta charset="UTF-8">` present
5. **Lang attribute** — `<html lang="...">` matches the page's locale
6. **Viewport** — `<meta name="viewport" content="width=device-width, initial-scale=1.0">`
7. **Title** — present, length 10–60 chars, unique across all checked pages
8. **Description** — present, length 50–160 chars, unique
9. **Canonical** — present, absolute URL, points to self (or to a valid primary)
10. **hreflang** — one tag per locale + `x-default`, symmetric, absolute URLs
11. **Open Graph** — `og:type`, `og:title`, `og:description`, `og:url`, `og:image`, `og:site_name`, `og:locale` all present
12. **Twitter Card** — `twitter:card` (summary_large_image), `twitter:title`, `twitter:description`, `twitter:image`
13. **Structured data** — at least one `<script type="application/ld+json">` if `json_ld_required: true`. Validate JSON parses.
14. **H1** — exactly one `<h1>` per page, non-empty
15. **Images alt** — every `<img>` has non-empty `alt` (warn, not fail)
16. **noindex check** — public pages must NOT contain `<meta name="robots" content="noindex">`
17. **OG image** — fetch `og_image` URL, verify HTTP 200 and Content-Type starts with `image/`
18. **Yandex verification** (if `yandex_verification: true`) — `<meta name="yandex-verification">` present on `/`

#### Check group C — cross-page

19. **Title uniqueness** — no two pages share the same `<title>`
20. **Description uniqueness** — no two pages share the same description
21. **Canonical loops** — no page's canonical points to a 404 or to a non-canonical URL

### Step 3: Output

For each check, print as it runs:

```
[i/N] Check Name -- checking...
[i/N] Check Name -- PASS
```

or

```
[i/N] Check Name -- FAIL: <one-line reason, with URL>
```

or

```
[i/N] Check Name -- WARN: <one-line reason>
```

**Run ALL checks** even if earlier ones fail.

### Step 4: Summary

After all checks, print a table grouped by severity:

```
## SEO Audit Summary

### FAIL (must fix)
| Check | URL | Issue |
|-------|-----|-------|
| ... | ... | ... |

### WARN (should review)
| Check | URL | Issue |
|-------|-----|-------|
| ... | ... | ... |

### PASS
N checks passed
```

### Step 5: Verdict

- All PASS → "SEO в порядке"
- Any FAIL → "Найдены критичные проблемы — нужно править"
- Only WARN → "Критики нет, есть что улучшить"

## Implementation notes

- Use `curl -sS -L -A "Mozilla/5.0 (compatible; SEOAudit/1.0)" -o /tmp/seo-page.html -w "%{http_code}" {url}` for HTML fetch
- For HEAD checks: `curl -sSI -o /dev/null -w "%{http_code}" {url}`
- Parse HTML with a small bun script using regex or `cheerio`-like extraction. Don't pull heavy deps — inline regex for `<title>`, `<meta>`, `<link>`, `<h1>`, `<html lang>` is fine.
- Static landings (server-rendered) work with curl. SPA routes (rendered client-side) need a noindex check on the source HTML — if a public route relies on JS rendering for SEO content, flag it as FAIL.
- Network calls have retries (3 attempts, 2s backoff) — see global retry rule.

## Config format

The local file `./tests/skills/seo-check.md` should contain:

```markdown
# SEO Check — {ProjectName}

## Site
- production: https://example.com
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

## Skip checks
(optional — list check numbers to skip with reasoning)
- 15 (images alt) — landing pages have decorative SVGs only

## On success
SEO в порядке

## On failure
Найдены критичные проблемы
```

## Rules

- **Read-only.** Never edit any file. Report only.
- **Production by default.** Audit the production URL unless user explicitly asks for a dev stand.
- **Communicate in Russian.**
- **Don't fix anything.** If user wants fixes, that's a separate task.
