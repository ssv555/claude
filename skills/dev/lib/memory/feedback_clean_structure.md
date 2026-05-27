---
name: feedback_clean_structure
description: Keep generated scripts and their outputs together in one folder, not scattered across directories
type: feedback
---

All related files (script + its output) must live in one folder. Don't scatter script in one place and results in another.

**Why:** User explicitly corrected this — putting script in `.tmp/` root and results in a subfolder is messy. Everything related to one task should be self-contained in one directory.

**How to apply:** When creating utility scripts, create a dedicated folder for the script AND its output. Name it concisely per user's choice. Script name should also be short (e.g. `gen.ts`, not `generate_wg_allowed_ips.ts`).
