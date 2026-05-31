---
name: dev-merge
description: Chief-only — review and merge a developer's branch into main. Two modes: (1) /dev-merge <alias> lists all open unmerged branches for that dev; (2) /dev-merge <sha> finds branch by HEAD sha and runs full merge pipeline (pre-deploy-check-build + autotests + merge + push + cleanup). Use when user says "/dev-merge <alias>", "/dev-merge <sha>", "слить ветку", "принять работу".
model: opus
allowed-tools: Bash(*), Read(*), Grep(*), Glob(*), Edit(*), Write(*)
---

# dev-merge

Принять ветку разработчика. **Только шеф (ssv555 / PC-SKY).**

## Status block

```
SKILL:  dev-merge
MODEL:  opus
```

## Доступ — только шеф

```powershell
if (-not (($env:USERNAME -eq 'ssv555') -or ($env:COMPUTERNAME -eq 'PC-SKY'))) {
    Write-Error "Forbidden: chief-only skill"
    exit 1
}
```

## Два режима

### Режим 1 — `/dev-merge <alias>` → список открытых веток

Аргумент соответствует паттерну `[a-z][a-z0-9_]{2,15}` (нет `/`, нет `[0-9a-f]{7,}`).

1. SSH на moscow_my, получить все незамердженные ветки этого дева:
   ```bash
   ssh moscow_my "git -C /srv/git/VDole.git for-each-ref \
     --format='%(objectname:short) %(refname:short) %(committerdate:relative) %(authorname)' \
     'refs/heads/dev/<alias>/' \
     --sort=-committerdate"
   ```
   Фильтр «незамердженные»: ветки, которые ещё существуют в bare-репо = незамердженные (merged → /dev-merge удаляет их).

2. Для каждой ветки добавить stat:
   ```bash
   git -C /srv/git/VDole.git log --oneline "refs/heads/dev/<alias>/<slug>" "^refs/heads/main" | wc -l
   git -C /srv/git/VDole.git diff --shortstat "refs/heads/main" "refs/heads/dev/<alias>/<slug>"
   ```

3. Вывести таблицу:
   ```
   Open branches for dev: <alias>

   sha      branch                      date          commits   diff
   ───────────────────────────────────────────────────────────────────
   abc1234  dev/spc/add-email-field     2 hours ago   3         +45/-12
   def5678  dev/spc/fix-login-redirect  1 day ago     1         +8/-3

   To merge: /dev-merge <sha>
   To analyze: /dev-changelog <sha>
   ```

4. Если веток нет → «нет открытых веток у <alias>».

---

### Режим 2 — `/dev-merge <sha>` → полный merge pipeline

Аргумент — short sha (7+ hex chars) из TG-нотификации или из таблицы выше.

1. **Chief-identity guard** (см. выше).

2. **Найти ветку по sha** на moscow_my:
   ```bash
   ssh moscow_my "git -C /srv/git/VDole.git for-each-ref \
     --format='%(objectname:short) %(refname:short)' refs/heads/dev/ | grep '^<sha>'"
   ```
   Нет совпадений → «ветка с sha `<sha>` не найдена в bare-репо — возможно уже смерджена».
   Несколько совпадений (sha collision) → показать все, попросить уточнить.
   Одно совпадение → взять `refname:short` как `BRANCH`.

3. **SHA-pin check** — сравнить текущий HEAD ветки на bare-репо с sha из аргумента:
   ```bash
   CURRENT_HEAD=$(ssh moscow_my "git -C /srv/git/VDole.git rev-parse --short refs/heads/${BRANCH}")
   ```
   Если `CURRENT_HEAD != <sha>` → предупреждение:
   > «Ветка `<BRANCH>` ушла вперёд после /dev-09-finish.
   > Было: `<sha>` (из TG/finish-log)
   > Сейчас: `<CURRENT_HEAD>` (N коммитов вперёд)
   > 1. Мердж current HEAD `<CURRENT_HEAD>` — дев добавил что-то после finish
   > 2. Отмена — скажи деву пересоздать /dev-09-finish»
   На «1» → продолжить с CURRENT_HEAD. На «2» → выйти.

4. **Подготовить рабочую копию шефа** (`D:\Data\Documents\Programming\Projects\WEB\VDole`):
   - Текущая ветка = `main`, WC чистый → иначе отказ.
   - `git fetch origin && git pull --rebase origin main`.

5. **Получить ветку дева из bare-репо на moscow_my:**
   ```bash
   git remote add moscow ssh://ssv@moscow_my:53847/srv/git/VDole.git  # если нет
   git fetch moscow dev/<alias>/<slug>
   git checkout -B review/<alias>/<slug> moscow/dev/<alias>/<slug>
   ```

6. **pre-deploy-check-build** → падает = стоп, показать ошибки.

7. **pre-deploy-autotests** → падает = стоп.

8. **Code review** (опционально, по явному запросу шефа): `code-reviewer`.

9. **Merge:**
   ```bash
   git checkout main
   git merge --no-ff review/<alias>/<slug> -m "Merge dev/<alias>/<slug>: <last subject>"
   ```
   Конфликт → стоп, дать шефу решить.

10. **Push на GitHub:**
    ```bash
    git push origin main
    ```

11. **Очистка:**
    - `git branch -D review/<alias>/<slug>` (локальная review-ветка шефа).
    - На moscow_my удалить ветку + триггернуть mirror:
      ```bash
      ssh moscow_my "sudo git -C /srv/git/VDole.git update-ref -d refs/heads/dev/<alias>/<slug> \
        && sudo touch /var/spool/vdole-mirror/queue"
      ```

12. **Итог:** branch, commits merged, +/- lines, status.

## Что НЕ делать

- Не мерджить без прохождения checks (без явного `--force` от шефа).
- Не `--squash` без указания (теряем authorship дева).
- Не `--force` в main.
- Не удалять main/master/prod/release/* ветки.
- Если в diff секреты (env, ключи) — стоп, не мерджить.
