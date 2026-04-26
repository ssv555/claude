# `<emp-NN-name>` — project addendum

> **Optional** project-local addendum to a role. Lives at `<project>/.claude/skills/employers/emp-NN-*.md` (preferred) or `<project>/.docs/employers/emp-NN-*.md` (legacy).
>
> Loaded by the global `~/.claude/skills/emp-NN-*/SKILL.md` AFTER `role.md` and `profile.md`. Use it ONLY for project-specific extensions that don't fit `profile.md` and shouldn't go into the universal role.

## When to use an addendum

✅ Use it for:
- Extra report sections specific to your project (e.g. for emp-01-analyst — a custom compliance subsection unique to your industry)
- Extra checklist items for the role's "Финальная проверка" specific to project conventions not generic enough for `profile.md`
- Project-specific Pass-1 CRIT rules (for emp-04-reviewer) that don't apply universally
- Stack constraints that affect ONLY this role (e.g. for emp-05-designer — fixed stylization API for THIS project's UI library variant)
- Override of a default sub-step where the project genuinely diverges from the universal flow

❌ DON'T use it for:
- Stack rules that affect everyone — those belong in `profile.md` → "Stack rules"
- Domain terminology — `profile.md` → "Domain & terminology"
- Sealed registry path or compliance items — `profile.md`
- Generic improvements to a role — propose to the universal `role.md` instead

## Format

The addendum is **additive**: it adds rules / checklist items / extra sections, it does NOT replace the universal role. The role reads `role.md` first, then `profile.md`, then this file. Conflicts: addendum wins on overlap, but keep overlap to a minimum.

Suggested structure:

```markdown
# emp-NN-<role> — `<PROJECT_NAME>` addendum

## Purpose

One paragraph: WHY this addendum exists for this project. What does this role do here that the universal `role.md` doesn't already cover?

## Extra rules / overrides

- <rule 1: ссылка на правило, на какой шаг роли влияет>
- <rule 2>

## Extra checklist items (for "Финальная проверка")

- [ ] <project-specific check 1>
- [ ] <project-specific check 2>

## Extra report sections (if any)

> Only if your project genuinely needs additional sections in the role's standard report (`01_ba.md`, `02_arch.md`, etc.).

### §X.Y — `<section name>`

<description of what this section contains and when it's filled>

## Project-specific examples (if useful)

<concrete examples that help the role calibrate>
```

## Examples of valid addendums

- **`emp-04-reviewer.md`** in a financial project: extra Pass-1.4 CRIT rules — "no float for money", "no plaintext PII in logs", "audit trail required for transactions over X", with grep patterns.
- **`emp-05-designer.md`** in a UI-heavy product: fixed UI library variant, project-specific Pass-Through stylization conventions, list of mandatory tokens.
- **`emp-02-architect.md`** in a regulated project: extra mandatory section in `02_arch.md` for "Compliance impact assessment" with sub-fields specific to the regulator.
