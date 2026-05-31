---
name: version-up
description: Increment APP_VERSION and update APP_VER_DATE in version.ts
disable-model-invocation: false
allowed-tools: Bash(pwd), Bash(ls *), Read, Edit
model: haiku
context: fork
---

Increment version and update date in the project's `version.ts`. **NEVER open the file in any external editor (Cursor, VS Code, etc.). Only Read + Edit tools.**

1. Get current working directory with `pwd`
2. Locate the version file. Try these paths in order, use the first that exists:
   - `{cwd}/back/src/shared/version.ts`   (VDole-style layout)
   - `{cwd}/server/shared/version.ts`     (legacy/iamrich layout)
   - `{cwd}/src/shared/version.ts`
3. Read the version file
4. Parse current `APP_VERSION` (format: "X.Y.ZZZ")
5. Increment patch version by 0.001:
   - "1.0.005" → "1.0.006"
   - "1.0.999" → "1.1.000"
6. Get current date in format "YYYY-MM-DD"
7. Edit file:
   - Update `APP_VERSION` with new value
   - Update `APP_VER_DATE` with current date
8. Output success message with new version

**Rules:**
- NEVER hardcode project path
- Always use relative path from current working directory
- Version format: `export const APP_VERSION = "X.Y.ZZZ";`
- Date format: `export const APP_VER_DATE = "YYYY-MM-DD";`
- Preserve exact file formatting and quotes
