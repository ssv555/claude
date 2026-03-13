---
name: git-save
description: Generate git command for add + commit (no push)
disable-model-invocation: true
allowed-tools: Bash(git *)
model: sonnet
context: fork
---

Analyze changes and generate git command:

1. Run `git status` to see unstaged/staged files
2. Run `git diff` to understand changes
3. Generate SHORT commit message (3-5 words in English) based on changes
4. Output ONLY the command in copyable code block:

```bash
git add -A && git commit -m "short message"
```

**Rules:**
- Message reflects change type: fix/add/update/refactor/remove
- NO explanations before/after
