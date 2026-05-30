# Правила для разработчиков на `moscow_my` / Rules for Developers on `moscow_my`

> 🇷🇺 Прочитай правила. После прочтения попросят ввести `YES, I AGREE` для принятия.
> Пока не принял — shell тебя выкинет. Чтобы отказаться явно — введи `NO` (тебя залогаутит).
>
> 🇬🇧 Read the rules. After reading you'll be prompted to type `YES, I AGREE` to accept.
> Until you accept, the shell logs you out. To decline explicitly — type `NO` (also logs you out).

Принятие записывается в audit-log с alias, временем и SHA-256 хешем этого файла.
Если правила обновятся — хеш изменится, и при следующем логине попросят принять заново.

Acceptance is recorded with your alias, timestamp, and the SHA-256 hash of this
file. If the rules change, you'll be asked to accept the new version on next login.

Эти правила — **технические обязательства по workflow**. Они **отдельны от NDA**
(`~/AGREEMENT.md`), который покрывает конфиденциальность и интеллектуальную собственность.

These are TECHNICAL workflow obligations. They are SEPARATE from your NDA
(`~/AGREEMENT.md`), which covers confidentiality and intellectual property.

---

## 1. Один таск = один push / One task per push — never bundle tasks

🇷🇺 Каждый `git push` должен содержать коммиты ровно по ОДНОЙ задаче. Смешивать две
и более независимых задачи в одном пуше — **запрещено**.

- Две задачи → две ветки → два пуша → два ревью. Никогда не комбинировать.
- «Заодно поправил» (стиль, опечатка, посторонняя чистка) — это ОТДЕЛЬНАЯ задача.
  Делай через `/dev-00-start`, пушь отдельно.
- Заметил другую проблему по ходу → СНАЧАЛА доделай текущую задачу, запушь её,
  и только потом открывай новую ветку под вторую.
- Зачем: ревью идёт по веткам. Смешанный пуш заставляет шефа разбирать несвязанные
  изменения; это болезненно и через это просачиваются баги.

🇬🇧 Each `git push` must contain commits for exactly ONE task. Mixing two or more
independent tasks in a single push is **forbidden**. Two tasks → two branches → two
pushes → two reviews. Drive-by fixes are SEPARATE tasks. Review is per-branch;
mixed pushes force the chief to untangle unrelated changes — that's how bugs slip through.

## 2. Никогда не пушь в защищённые ветки / Never push to protected branches

🇷🇺 `main`, `master`, `prod`, `production`, `release/*` — защищены. Серверный
`pre-receive` хук всё равно отклонит такой push, но **не пытайся**. Если оказался
на защищённой ветке — используй `/dev-00-start`, он переключит на твою
`dev/<alias>/<slug>`. Запрещено: `--force`, `--force-with-lease`, `--no-verify`
(без явного письменного согласия шефа).

🇬🇧 Protected branches block your push at the server. Use `/dev-00-start` to switch
to your `dev/<alias>/<slug>`. Forbidden: `--force`, `--force-with-lease`,
`--no-verify` without explicit chief approval in writing.

## 3. Не пиши в chief-owned пути / Don't write to chief-owned paths

🇷🇺 `/opt/claude-shared/*`, `/opt/dev-skill/*` — **read-only**. `~/.claude/skills/`,
`~/.claude/CLAUDE.md`, `~/.claude/codex.md`, `~/.claude/DEV_GUIDE.md` — симлинки
на shared, не перезапишешь. Свою `~/.claude/memory/` — можно, Claude сам её
обновляет под тебя.

🇬🇧 `/opt/claude-shared/*` and `/opt/dev-skill/*` are read-only. The shared files
in `~/.claude/` are symlinks — won't write. Your own `~/.claude/memory/` IS
writable; Claude updates it for you.

## 4. Не читай чужие home / Don't read other developers' homes

🇷🇺 `/home/<other-alias>/*` — не твоё. Даже если права случайно разрешили — не
смотри. Все shell-команды логируются. Не подсматривай за чужими процессами в `ps`
(стоит `hidepid`, но правило остаётся).

🇬🇧 `/home/<other-alias>/*` is not yours. Even if filesystem perms accidentally
allowed it, you must not look. All shell commands are logged.

## 5. Никаких секретов в репо / No secrets in the repo

🇷🇺 `.env*`, приватные ключи (`*.pem`, `id_*`), токены, пароли — **никогда не коммить**.
Pre-receive хук имеет best-effort защиту от очевидных паттернов, но это **не лицензия**.
Случайно закоммитил секрет → СТОП, шефу немедленно.

🇬🇧 `.env*`, private keys, tokens, passwords — never commit. The pre-receive hook
scans for obvious patterns but is best-effort, not a license. If you accidentally
committed a secret, STOP, tell the chief immediately.

## 6. Осмысленные commit messages / Meaningful commit messages

🇷🇺 Префиксы: `feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:`.
Императив present, ≤72 символов в первой строке. Body объясняет **почему**, а не
**что** (diff и так показывает что).
- Плохо: `fix stuff`, `wip`, `update`, `1`.
- Хорошо: `fix: trim trailing space in email validator before lookup`.

🇬🇧 Same prefixes. Imperative present, ≤72 chars summary. Body explains WHY, not WHAT.

## 7. Вся shell-активность логируется / All shell activity is logged

🇷🇺 Каждая команда на сервере захватывается в audit-логи доступные шефу:
`last`, `journalctl _UID=<твой-uid>`, shell history,
`/opt/claude-shared/audit/<YYYY-MM>/<твой-alias>.log` (вызовы скилов).
Это **для твоей же защиты** — если что-то сломалось, лог подтвердит что не ты.

🇬🇧 Every command captured in audit logs available to the chief. This is for your
protection too — if something blows up, the log proves it wasn't you.

## 8. Не обходи технические ограничения / Don't bypass technical limits

🇷🇺 SFTP/SCP/WinSCP отключены намеренно. Не пытайся обойти (base64 через буфер
обмена, скриншоты кода, screen-record). Обход ограничений трактуется как
нарушение NDA. Канал для кода — только `git push`.

🇬🇧 SFTP/SCP/WinSCP are disabled on purpose. Working around the limits (clipboard
base64, screenshots, screen-record) is treated as an NDA violation. Use `git push`
to ship code.

## 9. Закрывай задачу через `/dev-09-finish` / End every task with `/dev-09-finish`

🇷🇺 Когда ветка готова к мерджу — `/dev-09-finish`. Он: прогонит pre-deploy
проверки, прогонит автотесты, запушит финальное состояние, уведомит шефа в TG,
запишет в audit-log. Не пингуй шефа вручную «замерджи плз» — скил делает это
правильно со всей метадатой.

🇬🇧 When your branch is ready for the chief — run `/dev-09-finish`. It runs
pre-deploy checks, autotests, final push, chief notification, audit log entry.
Don't ping the chief manually — the skill does it right with all metadata.

## 10. Не уверен — спрашивай / Ask when in doubt

🇷🇺 Лучше задать один очевидный вопрос, чем выкатить код который что-то сломает.
Шеф предпочитает уточняющий вопрос полу-правильной догадке.

🇬🇧 Better to ask one obvious question than to ship code that breaks something.
The chief prefers a clarifying question over a half-correct guess.

---

## Принятие / Acceptance

🇷🇺 Введя `YES, I AGREE` в приглашении, ты подтверждаешь:
- Прочитал все 10 правил.
- Понимаешь что нарушения могут стоить тебе доступа к серверу и проекту, и
  повлечь юридические последствия по NDA который ты тоже подписывал.
- Твоё принятие логируется с alias, временем и хешем этого файла на момент принятия.

Если **НЕ согласен** — введи `NO`, или просто Enter. Тебя залогаутит без записи в
audit (только факт показа правил).

🇬🇧 By typing `YES, I AGREE`, you confirm you've read all 10 rules, understand
that violations may cost access and carry legal consequences, and accept the
acceptance being logged.

If you **don't agree** — type `NO` or just press Enter. You'll be logged out
without an acceptance entry (only the fact that you saw the rules is logged).

Вопросы — шефу напрямую. Не у других девов.
Questions go to the chief directly. Don't ask other devs.
