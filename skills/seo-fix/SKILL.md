---
name: seo-fix
description: Fix SEO issues found by /seo-check. Splits findings into mechanical (auto-fix) and content (interactive per-item with AskUserQuestion). Edits source files (templates, sitemap, robots, locales) — never patches the deployed site directly. Reads project-specific config from ./tests/skills/seo-check.md plus optional ./tests/skills/seo-fix.md
disable-model-invocation: false
allowed-tools: Bash(bun *),Bash(curl *),Bash(magick *),Bash(convert *),Read,Write,Edit,Glob,Grep,AskUserQuestion
model: sonnet
---

# SEO Fix — Universal Repairer

Apply fixes to SEO issues. Two categories:

- **Mechanical** — deterministic (add missing meta tag, swap 302→301, regenerate sitemap, compress OG image). Applied without per-item confirmation.
- **Content** — creative (rewrite title/description, generate alt text, CTA copy, trust signals). Applied **interactively, one at a time** via `AskUserQuestion`.

Edits **source files only** (eta templates, locale JSONs, public/sitemap.xml, public/robots.txt, image files in public/img/). Never SSH to a server, never patch the running site.

## Execution

### Step 0: Acquire findings

Findings come from one of three sources, in priority order:

1. **From the calling /seo-check** — if invoked right after `/seo-check`, the summary table from the previous turn IS the input. Re-read the conversation context to extract FAIL + WARN rows.
2. **From user message** — user pastes a findings block or specific check numbers (e.g. "fix 7, 11, 22").
3. **Independent scan** — if neither available, ask user: "Запустить /seo-check сначала?" → if yes, STOP and let them run it. Don't re-implement check logic here.

### Step 1: Read configs

- `./tests/skills/seo-check.md` — site config (production URL, locales, public URLs, paths to sitemap/robots, og_image expectations, selling expectations).
- `./tests/skills/seo-fix.md` — optional fix-specific config: source-of-truth file paths (template engine + path patterns, locale file structure, where meta tags live in code). If absent, infer from project structure.

### Step 2: Categorize findings

Split each finding into one of three buckets. Print the categorization as a table BEFORE doing anything:

```
## Findings to fix (N total)

### Mechanical (M items — will auto-fix)
| # | Check | URL | Fix action |

### Content (C items — will ask per item)
| # | Check | URL | Issue |

### Skipped (S items — outside scope)
| # | Check | Reason |
```

**Mechanical bucket** — apply automatically:
- Missing canonical / hreflang / OG / Twitter Card / charset / viewport / lang attribute (add per template)
- Missing `Disallow:` entry in robots.txt
- Missing/stale `<lastmod>` in sitemap.xml (set to today)
- URL absent from sitemap (add entry with sensible defaults)
- 302 → 301 swap for permanent redirects (in nginx/server config OR in app router — flag if user owns the file)
- Redirect chain collapse (3xx → 3xx → 200 becomes single 301)
- JSON-LD missing → add baseline `Organization` + `WebSite` schema
- OG image wrong dimensions → resize to 1200×630 with `magick` / `convert` (preserve original as `.bak`)
- `<html lang>` mismatch → fix per template
- noindex on public page → remove the meta tag
- Duplicate canonical / hreflang tags → dedupe

**Content bucket** — interactive, one AskUserQuestion per item:
- Title length out of bounds (10–60) or duplicate
- Description length out of bounds (50–160) or duplicate
- H1 empty / weak / multiple
- Image alt missing (need semantic content)
- CTA above the fold missing or weak (Full mode)
- Value proposition unclear (Full mode)
- Trust signals missing (Full mode)
- Form friction (Full mode — too many fields)
- Heading hierarchy skips (need user to decide demote/insert)
- Title/description rewrite for uniqueness

**Skipped bucket** — out of scope for this skill, report to user:
- Performance issues (LCP/CLS/INP) — needs separate optimization work
- Page weight > limit — needs asset optimization
- Mobile UX issues (tap targets, font size) — design decision
- Internal linking depth — IA decision
- Broken internal links to pages that don't exist — needs content decision (create page? rewrite link?)

### Step 3: Apply mechanical fixes

For each mechanical item, print BEFORE:

```
[i/M] Mechanical: {check} on {url} -- fixing in {file_path}...
```

Apply the edit. Print result:

```
[i/M] Mechanical: {check} -- DONE ({short summary of change})
```

or

```
[i/M] Mechanical: {check} -- SKIPPED ({reason — e.g. file not under repo control})
```

**File-resolution rules**:
- Meta tags in eta templates → find via Grep on `<head>` or `<meta name="..."` patterns, edit in-place.
- Meta tags in React component (`<Helmet>` / `next/head` / etc.) → find component, edit.
- robots.txt / sitemap.xml → typically in `public/` or `static/` — find via Glob, edit directly.
- Locale strings → `front/public/locales/{lang}/translation.json` (or whatever `i18n` setup uses).
- Images → `public/img/`, `static/img/`, etc. Use ImageMagick CLI for resize:
  ```bash
  magick "{src}" -resize 1200x630^ -gravity center -extent 1200x630 "{src}"
  ```
- Server redirects → if in repo (`nginx.conf`, `_redirects`, app router), edit. If on deploy server only — SKIP and report.

**Verification after each mechanical fix**:
- For HTML/template edits: re-read the file, confirm the inserted tag is present.
- For sitemap.xml: parse XML, confirm valid.
- For robots.txt: confirm syntax valid (no broken directives).
- For images: confirm new file dimensions match target.

### Step 4: Apply content fixes (interactive)

For each content item, use `AskUserQuestion`. Format depends on type:

#### Pattern A — title/description rewrite

> Title `/welcome_agents` (RU): сейчас "Лендинг для предпринимателей платформы инвестиций VDole" (78 символов, нужно 10–60).
>
> Предлагаемые варианты:

Options:
| Option | Label | Description |
|--------|-------|-------------|
| 1 | Стань Агентом VDole — продай долю в бизнесе (52 chars) | короткий + value prop |
| 2 | VDole — инвестиции в твой бизнес от частных лиц (49 chars) | акцент на инвестора |
| 3 | Свой вариант | пользователь введёт текст в следующем сообщении |
| 4 | Пропустить | оставить как есть |

After choice (1 or 2): apply edit to locale file. Choice 3: ask follow-up text question. Choice 4: skip.

#### Pattern B — alt text for image

> Image `/img/hero-investor.webp` on `/welcome_contragents` — alt отсутствует.
>
> Картинка: [показать .playwright-mcp/seo-ru-welcome_contragents-desktop.png если есть]

Options:
| Option | Label | Description |
|--------|-------|-------------|
| 1 | Инвестор просматривает офферы на смартфоне | дескриптивный |
| 2 | Главная иллюстрация раздела для инвесторов | функциональный |
| 3 | Свой текст | пользователь введёт |
| 4 | Декоративная (alt="") | отметить как декоративную |
| 5 | Пропустить | |

#### Pattern C — H1 / CTA / value prop rewrite

> H1 на `/welcome_service` — "Сервис" (слабо, не объясняет ценность).
>
> Предлагаемые варианты:

Options + free text + skip.

**Apply each accepted edit immediately** — don't batch. After applying, print:

```
[i/C] Content: {check} -- DONE (выбрано: option {N})
```

or:

```
[i/C] Content: {check} -- SKIPPED
```

### Step 5: i18n key sync

If any text edit touched a locale file in one language but the other language has the same key — ask user whether to also update the other locale (machine-translate suggestion + user confirms). Never silently leave locales out of sync.

### Step 6: Post-fix verification

After all fixes applied:

1. Re-run a **subset** of `/seo-check` Quick mode on the touched URLs only — verify the fixes actually resolved the findings.
2. Print delta:
   ```
   ## Verification
   | Finding | Before | After |
   | Title /welcome_agents length | 78 (FAIL) | 52 (PASS) |
   | Missing canonical / | absent (FAIL) | present (PASS) |
   ```
3. If any finding still FAILs after fix — report it as "needs manual investigation" with the original URL/file/issue.

### Step 7: Summary

```
## SEO Fix Summary

### Applied
- Mechanical: M/M
- Content: C_done/C_total (skipped: C_skipped)

### Files touched
- [front/src/static/partials/_head.eta](front/src/static/partials/_head.eta)
- [front/public/locales/ru/translation.json](front/public/locales/ru/translation.json)
- [front/public/locales/en/translation.json](front/public/locales/en/translation.json)
- [front/public/sitemap.xml](front/public/sitemap.xml)
- ...

### Still failing (manual work)
- {finding} — {reason}

### Recommended next steps
- Запустить /version-up (если правились locales)
- Запустить /seo-check заново для полной верификации
- Закоммитить
```

## Implementation notes

- **Use Edit, not Write**, for in-place file changes — preserve everything not touched.
- **Atomic edits**: one finding = one edit. Don't combine unrelated changes.
- **Locale edits**: use Read → JSON.parse → set key → Write back with stable formatting (2-space indent, sorted keys if file already sorted).
- **Image resize**: prefer `magick` (ImageMagick 7), fall back to `convert` (IM6). Always preserve original as `{name}.bak.{ext}` BEFORE overwriting. Verify dimensions after with `magick identify`.
- **eta templates**: meta tags use `<%= it.meta.foo %>` interpolation — never hardcode values, edit the data source (a JSON file or TS module that supplies `meta`).
- **Project conventions**: respect existing patterns. If project uses `<RouteHeader>` / `<DocumentMeta>` / similar wrapper, edit through the wrapper, not raw `<head>`.
- **i18n bumps**: if any `front/public/locales/**` file changed, remind user to run `/version-up` (per VDole CLAUDE.md rule). Other projects may have own conventions — check.

## Config format (optional)

`./tests/skills/seo-fix.md`:

```markdown
# SEO Fix — {ProjectName}

## Source-of-truth paths

- Meta data source: front/src/static/data/meta.{lang}.ts
- Templates: front/src/static/partials/_head.eta
- Locales: front/public/locales/{lang}/translation.json
- Sitemap: front/public/sitemap.xml (regenerated by `bun run build:sitemap`)
- Robots: front/public/robots.txt
- Images: front/public/img/

## Image conventions

- OG default: 1200x630 webp + png fallback
- Hero images: max 1920px wide, webp preferred

## After-fix hooks

- Locale changes → suggest /version-up
- Sitemap changes → run `bun run validate:sitemap`

## Skip rules

- Don't touch nginx config (managed manually on server)
- Don't auto-rewrite ru → en (translations are reviewed manually)
```

## Rules

- **Edits source files only.** Never deploy, never SSH, never modify built artifacts in `dist/`.
- **One AskUserQuestion per content item.** No batching content decisions.
- **Communicate in Russian.**
- **Show diffs in chat** for non-trivial edits — let user see what changed.
- **Always re-verify** after fixing (Step 6) — don't claim success without proof.
- **Don't expand scope.** If user asked to fix #7 only, don't also fix #8 because you noticed it.
- **Respect ASK BEFORE EXTRA CHANGES** — anything not in the findings list requires user approval before touching.
