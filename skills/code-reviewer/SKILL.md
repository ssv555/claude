---
name: code-reviewer
description: "Run project-aware code review (SOLID, OOP, DRY, Security) using the code-reviewer agent. Use when the user wants a deep architecture review of changed code."
metadata:
  version: 1.0.0
---

# Code Reviewer

Launch the `code-reviewer` agent to review all changed code in the current project.

## Instructions

Use the Agent tool to spawn the `code-reviewer` agent:

```
subagent_type: code-reviewer
prompt: Review all changed code in this project.
```

Do NOT perform the review yourself — delegate entirely to the agent. When the agent returns results, display them to the user as-is.
