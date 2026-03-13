---
name: version-up
description: Increment APP_VERSION and update APP_VER_DATE in version.ts
disable-model-invocation: false
allowed-tools: Bash(pwd), Bash(*cursor.cmd*), Read, Edit
model: haiku
context: fork
---

Increment version and update date in `server/shared/version.ts`.

**CRITICAL: Execute steps strictly in order. Do NOT run steps in parallel. Complete each step before starting the next.**

1. Get current working directory with `pwd` and construct absolute path: `{cwd}/server/shared/version.ts`
2. **FIRST — Open file in Cursor IDE** (must complete before any other action):
   ```bash
   "$LOCALAPPDATA/Programs/Cursor/resources/app/bin/cursor.cmd" "{absolute_path}"
   ```
   Wait for this to finish before proceeding.
3. Read the version file
4. Parse current `APP_VERSION` (format: "X.Y.ZZZ")
5. Increment patch version by 0.001:
   - "1.0.005" → "1.0.006"
   - "1.0.999" → "1.1.000"
7. Get current date in format "YYYY-MM-DD"
8. Edit file:
   - Update `APP_VERSION` with new value
   - Update `APP_VER_DATE` with current date
9. Output success message with new version

**Rules:**
- NEVER hardcode project path
- Always use relative path from current working directory
- Version format: `export const APP_VERSION = "X.Y.ZZZ";`
- Date format: `export const APP_VER_DATE = "YYYY-MM-DD";`
- Preserve exact file formatting and quotes
