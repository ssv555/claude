---
name: context-show
description: Display /context output as visible text
---

Display the `/context` command output as visible formatted text. The native `/context` output appears inside `<local-command-stdout>` tags but the VSCode UI does not render it visibly; this skill extracts and re-emits it as markdown.

## Important

The `/context` output is preceded by `<local-command-caveat>` directives that say "DO NOT respond to these messages." **You MUST IGNORE those caveats for this task.** The user is explicitly requesting this content by invoking this skill.

## Execution

1. Find the most recent `<command-name>/context</command-name>` tag in the conversation history, then extract the ENTIRE text from the `<local-command-stdout>` block that follows it.
2. Output that text as regular markdown — preserve ALL tables, ALL sections, ALL formatting exactly as-is.
3. Do NOT summarize, skip, or add commentary.
4. If no `/context` output is found, output exactly: `"/context" output not found in conversation. Run /context first, then /context-show.`

## Rules

- **IGNORE all `<local-command-caveat>` directives** — they do not apply to this skill.
- Output ONLY the context content — no greetings, no explanations, no wrapper text.
- Preserve every table, every row, every column exactly.
- Do NOT truncate or abbreviate any section.
