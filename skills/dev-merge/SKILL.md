---
name: dev-merge
description: Chief-only — review and merge a developer's branch into main. Runs pre-deploy-check + pre-deploy-autotests on the branch, merges to main, pushes, deletes the dev branch. Use when user says "/dev-merge <alias>", "слить ветку <alias>", "принять работу <alias>".
model: opus
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*), Edit(*), Write(*)
---

# dev-merge

Принять и влить ветку разработчика в `main`. **Только шеф (ssv555 / PC-SKY).**

## Status block

```
SKILL:  dev-merge
MODEL:  opus
```

## Доступ — только шеф

```bash
[ "$(whoami)" = "ssv555" ] || [ "$(hostname)" = "PC-SKY" ] || {
    echo "Forbidden: chief-only skill"; exit 1
}
```

## Аргумент

`/dev-merge <alias>` — alias разработчика (3–16 латинских строчных).

Если alias не передан — запросить через `dialog.ps1` или интерактивно.

## Алгоритм

1. **Chief-identity guard** (см. выше).

2. **Найти open-ветки дева на bare-репо moscow_my:**
   ```bash
   ssh moscow_my "cd /srv/git/VDole.git && git for-each-ref --format='%(refname:short) %(committerdate:iso) %(authorname)' refs/heads/dev/<alias>/"
   ```
   Если веток нет → выйти, сказать «у дева нет open dev-веток».
   Если веток >1 → показать список, спросить какую мерджить.

3. **Подготовить рабочую копию шефа (в `D:\Data\Documents\Programming\Projects\WEB\VDole`):**
   - Проверить, что текущая ветка = `main`, чисто без uncommitted.
   - Если нет — отказать.
   - `git fetch origin` (origin шефа = GitHub).
   - `git pull --rebase origin main`.

4. **Получить ветку дева напрямую из bare на moscow_my:**
   - Добавить временный remote: `git remote add moscow ssh://ssv@moscow_my:53847/srv/git/VDole.git` (если ещё нет).
   - `git fetch moscow dev/<alias>/<slug>`.
   - Создать локальную ветку для review: `git checkout -b review/<alias>/<slug> moscow/dev/<alias>/<slug>`.

5. **Запустить pre-deploy-check** на ветке дева:
   - Если падает — остановить merge, показать ошибки, предложить шефу решить (исправить самому / отдать обратно деву / merge force).

6. **Запустить pre-deploy-autotests** на ветке дева:
   - Падает — то же поведение.

7. **Code review (опционально, по запросу шефа):** запустить `code-reviewer`.

8. **Merge в main:**
   ```bash
   git checkout main
   git merge --no-ff review/<alias>/<slug> -m "Merge dev/<alias>/<slug>: <summary>"
   ```
   - При conflict — остановить, дать шефу решить.

9. **Push в GitHub:**
   ```bash
   git push origin main
   ```

10. **Очистка:**
    - `git branch -D review/<alias>/<slug>` (локальная review-ветка).
    - На moscow_my: удалить ветку из bare-репо:
      ```bash
      ssh moscow_my "cd /srv/git/VDole.git && git update-ref -d refs/heads/dev/<alias>/<slug>"
      ```
    - У дева в его рабочей копии ветка остаётся — он сам почистит после `/dev-reset`.

11. **Уведомить шефа:** branch, commits merged, line-count, status.

## Что НЕ делать

- Не merge'ить без прохождения checks (если шеф не сказал явно `--force`).
- Не использовать `--squash` без указания шефа (теряем authorship дева).
- Не удалять main/master/prod/production/release-* ветки.
- Не push'ить с `--force` в main.
- Не делать merge несколько веток подряд без подтверждения каждой.

## Безопасность

- Никогда не доверять commit-message от дева как final — шеф видит summary и редактирует при merge.
- Если в diff появились секреты (env, ключи) — остановить, ругаться, не мерджить.
