---
name: /app/ prefix for all SPA routes
description: Every React/SPA route in VDole must live under the /app/* URL prefix. Public/marketing pages stay at root (/, /welcome_*, /privacy, /terms) as static HTML.
type: feedback
originSessionId: edcc7361-8409-422f-ae5d-c308a5068aaf
---
All web-application (SPA) routes must start with `/app/`. This is a hard rule, not a recommendation.

**Why:** User stated during Session B migration — strict separation between public (SEO-targeted static HTML at root) and app (authenticated React SPA under `/app/*`). Keeps routing predictable and makes it obvious at URL-level whether a page is marketing or application.

**How to apply:**
- New SPA routes → file path under `front/src/routes/app/...` → URL `/app/{name}`
- New app-level `Link to=...` / `useNavigate({ to: ... })` → always prefix with `/app/`
- `/auth` and `/auth/callback/*` are the only exceptions (OAuth providers have fixed redirect URIs externally)
- Backend `ROUTE_SEO_META` keys must be `/app/*` only
- Legacy bookmarks (old `/home`, `/profile`, `/service/*`, `/403`) get 301 redirects to `/app/*` equivalents in `back/src/app.ts`
- **URL prefix is the ONLY criterion** for "app vs static" — never judge by page content. `/app/*` = application (subject to app-wide rules like base layouts, post-auth context, etc.) regardless of whether the page looks like a placeholder / about / dashboard. `/welcome_*` at root = static, do not touch. Do not ask "is this form-like or static-like?" when the user scopes work by prefix — the prefix has already answered.
