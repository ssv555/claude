# Employers — global pipeline-roles system

> Generic, project-agnostic implementation of the BA → Architect → [Designer] → Developer → Reviewer pipeline (`emp-NN-*`). Each role lives as a global skill at `~/.claude/skills/emp-NN-*/`, reads its universal "role spine" from the same folder, and project-specific stack/domain/rules from `<project>/.claude/skills/employers/profile.md`. New projects "join the system" by dropping in `profile.md` + `config.md`.

## Architecture (mirrors the `pre-deploy-check` global pattern)

```
~/.claude/skills/                              GLOBAL (universal across all projects)
  emp-00-orchestrator/
    SKILL.md         ← thin runner: load role.md, resolve project employers dir, read context, dispatch
    role.md          ← universal role spine: algorithm, autopilot, retry ladder, final.md template, boundaries
  emp-01-analyst/
    SKILL.md
    role.md          ← BA universal: report structure, INVEST, Gherkin AC, NFR, compliance, prohibitions
  emp-02-architect/
    SKILL.md
    role.md          ← Architect universal: 14-section report, ADRs, STRIDE, parallelization, design recommendation
  emp-03-developer/
    SKILL.md
    role.md          ← Developer universal: precise execution, self-gate, secrets sweep, parallel mode
  emp-04-reviewer/
    SKILL.md
    role.md          ← Reviewer universal: Mode A/B, OWASP, dependency audit, BA coverage, verdicts
  emp-05-designer/
    SKILL.md
    role.md          ← Designer universal: component-audit, screen-states, WCAG, i18n text-expansion, Principle 0
  employers/
    README.md             ← this file
    profile.template.md   ← what a project profile must contain
    config.template.md    ← runtime flags template
    role-addendum.template.md ← optional per-role project addendum

<project>/                                     PROJECT-LOCAL (per project)
  .claude/skills/employers/                    ← preferred (new) location
    profile.md                                 ← REQUIRED: domain, stack, terms, paths, rules cheat-sheet, sealed registry
    config.md                                  ← REQUIRED: runtime flags (use_subagents, interactive, report_language, …)
    emp-NN-*.md                                ← OPTIONAL per-role addendum (project-specific extra rules)
    pipeline/<slug>/                           ← per-task workspace (00_task → 01_ba → 02_arch → 02b_design → 04_dev → 03_review → final)
  .docs/employers/                             ← LEGACY back-compat path (used by VDole)
    profile.md, config.md, …                   ← same schema as above
```

## Path resolution (every emp-* SKILL.md does this)

Each global `emp-NN-*/SKILL.md` resolves the project employers folder by trying these paths in order, using the FIRST one found:

1. `<project_root>/.claude/skills/employers/`  ← preferred new location
2. `<project_root>/.docs/employers/`            ← legacy back-compat (VDole)

If neither exists → STOP with a bootstrap error showing the user the paths to create + the templates here in `~/.claude/skills/employers/`.

This guarantees:
- New projects can adopt the clean `.claude/skills/employers/` layout immediately.
- Existing projects (like VDole) keep working without moving files — just edit/add `profile.md` next to existing role cards in `.docs/employers/`.

## Read order at run time

When any `emp-NN-*` skill runs, it reads sources in this exact order (later sources override earlier on the same fact):

1. **Global universal:** `~/.claude/skills/emp-NN-*/role.md` — algorithm, structure, prohibitions
2. **Project runtime:** `EMPLOYERS_DIR/config.md` — flags
3. **Project profile:** `EMPLOYERS_DIR/profile.md` — domain, stack, paths, rules
4. **Project root:** `<project>/CLAUDE.md` — project rules
5. **Codex:** `~/.claude/codex.md` and/or `<project>/codex.md`
6. **Optional addendum:** `EMPLOYERS_DIR/emp-NN-*.md` — per-role overrides
7. **Pipeline state:** `<pipeline_root>/<slug>/00_task.md` and prior reports

## Bootstrapping a new project

1. Create the folder:
   ```bash
   mkdir -p <project>/.claude/skills/employers/pipeline
   ```
2. Copy templates:
   ```bash
   cp ~/.claude/skills/employers/profile.template.md  <project>/.claude/skills/employers/profile.md
   cp ~/.claude/skills/employers/config.template.md   <project>/.claude/skills/employers/config.md
   ```
3. Fill in `profile.md` — at minimum sections 1 (Identity), 2 (Domain), 3–4 (Stack + rules), 5 (Code paths), 7 (Self-gate commands), 9 (Sealed registry), 11 (Markdown link conventions).
4. Adjust `config.md` runtime flags (most defaults are fine).
5. Optionally add per-role addendums for project-specific extra checks.
6. Run `/emp-00-orchestrator <small task>` to verify the pipeline. Adjust `profile.md` based on what didn't work.

## Versioning notes

- The universal `role.md` is project-agnostic. Improvements here benefit all projects.
- Project-specific quirks live in `profile.md` and (if necessary) addendums.
- Rule of thumb: if you find yourself adding the same rule to two different projects' addendums, it should probably go into `role.md` (universal) instead.

## Known clients (as of migration)

- **VDole** — `.docs/employers/` legacy path. `profile.md` extracted from `CLAUDE.md`. Existing role cards (`emp-01-analyst.md` … `emp-05-designer.md`) preserved as project addendums after trim.

## Why this architecture

- **One source of truth per concern.** Stack rules in profile, role spine in global. No duplication.
- **Cheap to onboard new projects.** Two files (profile.md + config.md) is the minimum.
- **Existing projects don't break.** Back-compat path `.docs/employers/` keeps VDole and similar projects working without migration.
- **Optional per-role addendums.** Project quirks that don't fit profile (e.g. project-specific Pass-1 reviewer rules with custom grep patterns) go into a same-named file in the project's employers dir.
- **Consistent with other global skills.** `pre-deploy-check`, `pre-deploy-autotests`, `seo-check` all use the same "global runner reads project file" pattern.
