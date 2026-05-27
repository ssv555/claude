---
name: Dev testing URL
description: Always use vdole-ssv.it-joy.ru for testing — it proxies to local HMR via HTTPS
type: feedback
---

Always test on `vdole-ssv.it-joy.ru` — this is a reverse proxy to local dev server (localhost:32002) that provides HTTPS. NEVER go to localhost directly for testing. This is documented in CLAUDE.md under "Development Environment".

**Why:** User corrected multiple times. localhost doesn't have HTTPS which breaks OAuth callbacks and other features. The proxy handles SSL.

**How to apply:** When opening browser for testing, always use `https://vdole-ssv.it-joy.ru/...` URLs.
