---
name: tools-chatgpt-archive
description: Extract content from external ChatGPT / LLM share-links and archive it into the project's .docs/ knowledge base. TRIGGER automatically when the user posts a URL matching chatgpt.com/s/, chatgpt.com/share/, chat.openai.com/share/, claude.ai/share/, or similar external shared-chat links — even without an explicit command. Also runs on explicit request ("архивируй чат", "сохрани ссылку").
disable-model-invocation: false
allowed-tools: AskUserQuestion, Agent, Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(cat *), Bash(grep *), Bash(mkdir *), mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_evaluate, mcp__playwright__browser_click, mcp__playwright__browser_wait_for, mcp__playwright__browser_close, mcp__playwright_iso__browser_navigate, mcp__playwright_iso__browser_snapshot, mcp__playwright_iso__browser_evaluate, mcp__playwright_iso__browser_click, mcp__playwright_iso__browser_wait_for, mcp__playwright_iso__browser_close
model: sonnet
effort: high
---

Extract technical + ideological content from a shared external LLM conversation and merge it into the project's private `.docs/` knowledge base.

## When this skill runs

**Auto-trigger** on URLs matching:
- `chatgpt.com/s/...`
- `chatgpt.com/share/...`
- `chat.openai.com/share/...`
- `claude.ai/share/...`
- Other obvious shared-chat URLs from LLM providers

**Manual trigger** — user says "архивируй", "сохрани чат", "extract", "добавь в .docs" together with a URL.

If the URL is inside a larger message that also contains a direct question — answer the question FIRST, then offer to archive: "Архивировать ссылку в `.docs/`?". Don't silently archive while the user is waiting for an answer.

## Step 0: Ask user — which profile?

Before any extraction, ask the user how deep to process the link. Use `AskUserQuestion` with three options:

1. **По умолчанию** — Sonnet + high effort (this skill's own run). Fast, suits most marketing pages / product summaries / short chats.
2. **Глубоко** — spawn an Opus subagent to do the extraction. Best for long technical discussions, nested reasoning, multi-turn architectural chats. Costs more, ~2× slower.
3. **Быстро** — spawn a Haiku subagent. For obviously simple pages where defaults would be overkill.

Show the defaults explicitly in the question text (model + effort), so the user always sees what "default" means today and can change it if the skill's defaults drift.

**Question template:**

```
Ссылка: <URL>
Как обрабатывать?
  1. По умолчанию — Sonnet + high effort (я сам)
  2. Глубоко — Opus subagent (сложные чаты)
  3. Быстро — Haiku subagent (простые страницы)
```

Single AskUserQuestion call, three options. Don't chain dialogs; keep it to one question.

### Routing

- **Option 1 (default)** → continue with Steps 1–5 below, inline in this skill.
- **Option 2 (deep)** → call `Agent` with `subagent_type: "general-purpose"`, `model: "opus"`, and pass the full extraction brief (URL + Steps 1–4 condensed + expected output file path). The subagent returns a one-line summary; this skill just reports it to the user in Step 5.
- **Option 3 (fast)** → same as Option 2 but `model: "haiku"`.

**Subagent prompt template** (for deep/fast):

```
Extract content from this shared ChatGPT/LLM link and archive it into the project's .docs/ folder.

URL: <URL>
Project root: <cwd>

Steps:
1. Open the URL via mcp__playwright__browser_navigate. Wait for conversation DOM. Use browser_evaluate to extract user and assistant turns separately (selectors: [data-message-author-role="user"] and [data-message-author-role="assistant"]). Dedupe adjacent identical entries — shared pages often repeat. Close browser when done.
2. Filter: keep code/commands/versions/rationale/decisions/tradeoffs. Drop pleasantries, repetitions, abandoned branches.
3. Scan existing files in <cwd>/.docs/ (ls + skim filenames). Pick target:
   - Close-topic file exists → append new section "## YYYY-MM-DD — <topic>".
   - Otherwise → new file, matching existing naming convention in the folder (often UPPER_SNAKE_CASE English).
4. Write markdown following this structure:
   - # <Topic>
   - Short summary paragraph
   - ## Source — URL + archived date
   - ## Sections by topic
   - Footer: "Processed with: <model> + <effort>"
5. Return exactly one line to the parent: "<relative-path>|created|<one-line-topic-summary>" or "<relative-path>|appended|<one-line-topic-summary>".
```

Record the chosen profile (`Sonnet+high` / `Opus` / `Haiku`) — append it to the output file's footer (`Processed with: Opus`) so future-you can tell at a glance which runs were deep.

## Step 1: Open via Playwright (inline / default path)

WebFetch does NOT handle SPA-rendered chat pages — the content is empty. Always use Playwright MCP:

1. `browser_navigate` to the URL.
2. `browser_wait_for` until the conversation is rendered (wait for a message container, not just `load`).
3. `browser_evaluate` to extract the conversation DOM. Select user and assistant turns separately, dedupe:

```js
() => {
  const users = [...document.querySelectorAll('[data-message-author-role="user"]')].map(n => n.innerText);
  const asst  = [...document.querySelectorAll('[data-message-author-role="assistant"]')].map(n => n.innerText);
  const dedupe = a => a.filter((x, i) => x !== a[i - 1]);
  return { users, asst: dedupe(asst) };
}
```

4. If the page has embedded links that clearly carry relevant material (referenced code snippets, linked gists, related share pages) — follow them too.
5. `browser_close` when done.

Preferred MCP: `mcp__playwright__*`. If unavailable, fall back to `mcp__playwright_iso__*`.

## Step 2: Filter content

The raw dump is noisy. Keep only the valuable parts.

**Keep:**
- Code, commands, flags, file/package names, versions, config snippets.
- Rationale and ideology — WHY this approach, which alternatives were considered and rejected, tradeoffs.
- Concrete decisions, constraints, pitfalls, gotchas.
- Links to canonical docs / RFCs / PRs mentioned in the chat.

**Drop:**
- Pleasantries, apologies, "great question", "let me think".
- Repetitions and re-phrasings of the same idea.
- Dead-end branches that the user explicitly abandoned.
- Generic filler that any LLM would produce.

Aim: a dense technical note a senior engineer can read in 2 minutes, not a transcript.

## Step 3: Locate `.docs/` and pick the file

1. **Working directory** — the current project's root (`pwd`). `.docs/` lives there.
2. **Create if missing:** `mkdir -p .docs`.
3. **Ensure `.gitignore` covers it.** Grep `.gitignore` for a line matching `.docs/` or `.docs`. If absent — append `.docs/` to `.gitignore` and mention it in the final report. `.docs/` is a private knowledge base; it must never be committed.
4. **Scan existing files** in `.docs/` (`ls .docs/` + a quick skim of filenames and first lines) to find close topics. Match existing naming convention (look at other files — typical pattern is UPPER_SNAKE_CASE).
5. **Decide:**
   - Close-topic file exists → **append/merge** into it. Keep the existing structure; add a new section with a date-stamped subheading (`## YYYY-MM-DD — <topic>`) and the extracted content. De-duplicate: if the chat repeats something already in the file, skip it.
   - No close-topic file → **create new file**. English name, matching existing folder convention, descriptive (e.g. `REDIS_STREAMS_IPC.md`, `FONTS_SELF_HOSTING.md`). Not dated filenames — topic-based.

## Step 4: File format

Each `.docs/` file is Markdown. Standard structure:

```markdown
# <Topic>

Brief one-paragraph summary of what this file covers.

## Source

- <URL>  (archived YYYY-MM-DD)
- <additional-URL>  (if embedded links were followed)

## <Section 1 — e.g. "Decision" / "Approach">

...

## <Section 2 — e.g. "Code" / "Config">

...

## <Section 3 — e.g. "Rationale" / "Alternatives rejected">

...

---
Processed with: <model> + <effort>
```

When appending to an existing file, insert a new top-level or second-level section — don't rewrite the file's existing layout. Still add the `Processed with:` footer inside the new section, not at file bottom.

## Step 5: Report

One short message to the user:

- File path (relative from project root, as a clickable link).
- "Created" or "appended to".
- One-line summary of what was added (the actual topic, not "archived chat").
- Which profile was used (Sonnet+high / Opus / Haiku).
- If `.gitignore` was updated — mention it.

Example:
> Добавлено в [.docs/REDIS_STREAMS_IPC.md](.docs/REDIS_STREAMS_IPC.md) (append, Opus) — раздел про backpressure и consumer groups для Web↔Cryptograph.

Do not paste the full extracted content into chat — it's already in the file.

## Edge cases

- **Page requires login** — stop, tell the user: "Ссылка требует авторизации — открой её вручную и пришли текст, или дай публичный share-URL."
- **Page is empty after wait** — retry once (SPAs can be slow), then report the failure. Do not fabricate content.
- **Non-English content** — preserve the original language of the quoted material; section headers can be English.
- **User is working on an unrelated task** — archive quickly, report in one line, return to the original task. Don't derail. Still ask the Step 0 question — it's one click for the user.
- **No clear project root** (running outside a project) — ask where to save before proceeding.
