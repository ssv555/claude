# ~/.claude — индекс глобальной документации (Уровень 1)

> Носитель L1 для ГЛОБАЛЬНЫХ доков Claude (на все проекты). Каждый док — 1–2 строки: назначение + когда читать.
> Методология 4 уровней — VDole-проект: `…/WEB/VDole/docs/tech/optimization/DOCS_OPTIMIZATION.md`.
> Не доки (вне индекса): `skills/`, `hooks/`, `scripts/`, `memory/`, `projects/`, `docs/archive/`.

## Правила / поведение

- [CLAUDE.md](CLAUDE.md) — ядро глобальных поведенческих правил Claude, грузится КАЖДУЮ сессию всех проектов (status-блоки, Response Style, VERIFY, THINK/ASK/WAIT, SIMPLICITY, GOAL-DRIVEN, Git, RETRIES, file-links, chat pre-send). (383 стр, L4: → CLAUDE_deep.md)
  - [CLAUDE_deep.md](CLAUDE_deep.md) — L4: вынесенные ситуативные процедуры (TODO-заголовки, session storage, Personal Infra, browser-ping, batch CRLF, dev-skills, pwsh-примеры). Grep по разделу. (294 стр)
- [MEMORY.md](MEMORY.md) — индекс файловой памяти (ведётся подсистемой памяти, не оптимизировать вручную). (49 стр, L4: inline)

## Codex — правила качества кода

- [codex.md](codex.md) — сжатый чек-лист инженерных правил (1 строка на правило), применяется на каждой задаче; детали — в codex_description.md. (22 стр, L4: → codex_description.md)
- [codex_description.md](codex_description.md) — человеко-ориентированные пояснения ко всем принципам codex.md (SOLID/DRY/clean/security/perf/testing); AI этот файл не читает. (152 стр, L4: inline)

## Дизайн-инженерия (по триггеру «Deep Styles»)

- [codex.design.deep-styles.md](codex.design.deep-styles.md) — L3-обзор философии и правил Design Engineering (что/когда анимировать, easing, длительности, springs, a11y) + чек-лист. (124 стр, L4: → _deep)
  - [codex.design.deep-styles_deep.md](codex.design.deep-styles_deep.md) — L4: точные кривые/длительности, CSS/JS/Framer-сниппеты, spring-конфиги, clip-path, perf, Before/After/Why. (606 стр)

## Справочники — `docs/`

- [docs/google-sheets-write.md](docs/google-sheets-write.md) — чтение/запись Google Sheets из bun-скрипта через Service Account + googleapis (setup, операции, write-sheet.ts). (L4: inline)
