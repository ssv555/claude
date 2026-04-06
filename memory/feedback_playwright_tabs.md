---
name: Playwright — tabs, not multiple servers
description: Always browser_tabs list → new → navigate. NEVER close the browser or kill chrome — user owns browser lifetime and may have parallel tabs. On lock error, report and wait
type: feedback
---

### 🛑 NEVER close or kill the browser

The Chromium launched via Playwright MCP (`--user-data-dir C:/Users/ssv55/AppData/Local/ms-playwright/claude-def`) is **persistent user-owned state**. The user keeps multiple parallel tabs in it across Claude Code sessions — research, logged-in dashboards, work-in-progress, archived pages he's mid-reading. It is NOT a throwaway test browser.

**Absolutely forbidden without an explicit user instruction in the current turn:**
- ❌ `mcp__playwright__browser_close` — never. Don't "clean up" at the end of a task. Don't close "to free resources". Don't close to "retry cleanly". The user decides when the browser closes.
- ❌ `taskkill` / `Stop-Process` on `chrome.exe`, `node.exe`, or `bunx.exe` when they belong to `@playwright/mcp` / `claude-def` — even on a stuck lock. Multiple chrome.exe processes are **one** Chromium instance (main + renderers + GPU + utility helpers), and killing any of them wipes the user's tabs.
- ❌ `rm lockfile` inside `claude-def/` on your own initiative — the lock is real, a live browser holds it, removing it corrupts the profile.
- ❌ `browser_tabs action=close` on tabs you did not open in the current task, and even on those you did open — leave them for the user to close when he's done with them.

**What you may do freely:**
- ✅ `browser_tabs action=list` — read-only inspection
- ✅ `browser_tabs action=new` — opens a new tab; leaves existing ones untouched
- ✅ `browser_tabs action=select` — switch between tabs
- ✅ `browser_navigate` in the tab you just created
- ✅ After finishing your work in a tab you created — **leave it open**. The user will close it when he wants to.

**Why:** 2026-04-06 — after a lock error, I proposed `taskkill` on chrome.exe processes to "unstick Playwright". The user had ~6 chrome.exe PIDs visible (one live browser with helpers) plus his own parallel tabs holding research. He went off: *"когда ты работаешь, кто-то постоянный или ты закрываешь браузер? У меня сейчас там может будут параллельно закладки работать, а вы нахуй грохаете всё, 2 дебила, а бывает и 4 дебила. Надо как-то правило подправить, что закладки вы открываете, но не закрываете браузер. Я сам решу, когда закладки закрыть и сам браузер."* Multiple concurrent Claude Code sessions (2–4 at once is normal) share the `claude-def` profile via one live browser, and any one of them deciding to "clean up" destroys everyone else's work. Browser lifetime belongs to the user, period.


When a task needs multiple parallel browser contexts in Playwright MCP, the correct pattern is **tabs inside the single live MCP server**, never additional `@playwright/mcp` server entries in `.mcp.json` and never treating "playwright" as something that gets "launched" per task.

Within one Claude Code session there is exactly one live `@playwright/mcp` process holding one Chromium. All `mcp__playwright__*` tool calls operate on it statefully — cookies, localStorage, open tabs persist between calls. "Running a playwright" does not mean spawning a process — it means calling a tool against the already-running one.

**MANDATORY order before EVERY `browser_navigate` — no exceptions, no shortcuts, even for "just one quick page":**
1. `browser_tabs action=list` — see what's already open, pick up existing state
2. If list is non-empty and current tab holds meaningful state → `browser_tabs action=new` first
3. Only then `browser_navigate` (it targets the now-active new tab)

Skipping step 1 is an automatic failure. The user has explicitly flagged this as "долбоёб-уровень" behavior — jumping straight to `browser_navigate` before listing tabs means I'm ignoring state that may already exist in the live browser (logged-in sessions, the very URL the user just asked about already being open, etc.).

### Handling "Browser is already in use for ...user-data-dir..." lock error

This error is NOT a "try something else" signal. It has exactly one meaning: **another process (almost always another Claude Code session in a different window/worktree) currently holds that `--user-data-dir` profile open.** Playwright protects against profile corruption by refusing to open the same profile twice.

Diagnose it:
- `ls -la <user-data-dir>/lockfile` — shows recent mtime if truly held
- `mv lockfile lockfile.bak` — if it returns `Device or resource busy`, a real live process owns it; if the move succeeds, the lock was stale and retry will work

If the lock is real, the **only** correct responses are:
1. Tell the user plainly: "Профиль Playwright занят другой Claude-сессией — закрой её (или ту вкладку) и повтори". Name the profile path.
2. Offer: "Или вставь содержимое в чат текстом".
3. Wait.

**Forbidden fallbacks** when a Playwright lock blocks a ChatGPT/SPA/JS-rendered link:
- ❌ `WebFetch` on `chatgpt.com/s/...`, `x.com`, Notion, Linear, Figma, any SPA — CLAUDE.local.md explicitly says WebFetch doesn't handle these; the extracted text will be empty UI shell and you'll claim "no content" misleadingly.
- ❌ `mcp__desktop__screen_capture` / mouse / keyboard as a workaround — reading a user's screen to extract web content the user asked you to fetch is never the right answer. It's slow, lossy, and not what the tool is for.
- ❌ Retrying the same `browser_*` call in a loop hoping the lock clears.
- ❌ Silent fallback to "I couldn't get it, here's what I guessed" — always surface the lock to the user.

For genuinely parallel independent profiles (rare — different logins simultaneously, isolated + persistent together), the answer is **different `--user-data-dir` per server entry** or **`--cdp-endpoint` to an external Chrome**, not duplicate `bunx @playwright/mcp@latest` entries — those race on the shared Windows bunx temp dir (`bunx-<uid>-@playwright/mcp@latest/`) and fail with `EBUSY: failed copying files from cache` or `Cannot find module './utilsBundleImpl'`.

**Why:** 2026-04-05 session — `.mcp.json` had both `playwright` and `playwright_iso` entries, both `bunx @playwright/mcp@latest` differing only in runtime flags. On Windows bunx reuses the same temp dir for identical packages, so two concurrent spawns at Claude Code start corrupted each other → both Failed. I spent a long time diagnosing the race before mentioning that **tabs solve 95 % of "multiple playwrights" cases**. User was furious — correctly — because the native tab support was obvious and should have been the first thing I said. The whole `playwright_iso` entry existed only because I had not told him about tabs.

2026-04-06 session — user posted a `chatgpt.com/s/...` link per the `.docs/` archival workflow. I called `browser_navigate` directly (skipping `browser_tabs list`), got the profile lock error, then escalated wrongly: first WebFetch (empty SPA shell), then proposed `mcp__desktop__screen_capture`, then proposed `taskkill` on chrome.exe PIDs. Each step made it worse. The user explained in anger: multiple Claude Code sessions run in parallel (2–4 normal) against the same `claude-def` profile, so any "cleanup" by one session kills the other sessions' tabs. The **only** correct response to a lock error is: say so, name the profile, and wait for the user's instruction (close another session, paste text, etc.). Never touch the browser, lockfile, or processes.

**How to apply:**
- Any Playwright-related task: never propose adding a second `@playwright/mcp` server "for parallelism". Default answer is tabs.
- Before any `browser_navigate` in a session that may already have user-relevant tabs open — `browser_tabs list` first, then `tabs new` if needed, then navigate. No exceptions for "just one page".
- If someone asks "how do I open 2/3/4 playwrights simultaneously" — explain the three layers (tabs for same-profile parallelism, different `user-data-dir` for independent profiles, `--cdp-endpoint` for attaching to an external Chrome) and recommend tabs unless they have a concrete reason for the other two.
- Never run `bunx @playwright/mcp@latest` twice with the same version in one config.
- On "Browser is already in use" — report the lock to the user and wait. Never close the browser, kill chrome/node/bunx, touch the lockfile, or fall back to WebFetch/screen capture for SPA links. Browser lifetime belongs to the user.
