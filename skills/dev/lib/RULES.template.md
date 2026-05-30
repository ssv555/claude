# Rules for Developers on `moscow_my`

**These rules apply to every developer working on this server.** Read in full. After
reading you will be asked to type `YES, I AGREE` to accept. Until you accept, you
cannot use any interactive shell — you will be logged out.

Acceptance is recorded with your alias, timestamp, and the SHA-256 hash of this
file's current content. If the rules are updated, you will be asked to accept the
new version on next login.

These rules are TECHNICAL workflow obligations. They are separate from your NDA
(`~/AGREEMENT.md`), which covers confidentiality and intellectual property.

---

## 1. One task per push — never bundle tasks

Each `git push` must contain commits for exactly ONE task. Mixing two or more
independent tasks in a single push is **forbidden**.

- Two tasks → two branches → two pushes → two reviews. Never combine.
- "Drive-by" fixes (style, typo, unrelated cleanup) are SEPARATE tasks. Branch
  them out via `/dev-00-start`, push separately.
- If you notice another problem mid-task — finish the current task first, push it,
  then open a new branch for the second one.
- Why: review is per-branch. Mixed pushes force the chief to untangle unrelated
  changes; that's painful and that's how bugs slip through.

## 2. Never push to protected branches

- `main`, `master`, `prod`, `production`, `release/*` — protected.
- The server's `pre-receive` hook rejects such pushes anyway, but **don't try**.
  If you find yourself on a protected branch, use `/dev-00-start` to switch onto
  your own `dev/<alias>/<slug>`.
- Forbidden: `--force`, `--force-with-lease`, `--no-verify` (without explicit
  chief approval in writing).

## 3. Don't write to chief-owned paths

- `/opt/claude-shared/*` — shared skills and config, **read-only**.
- `/opt/dev-skill/*` — server-side scripts, **read-only**.
- `~/.claude/skills/`, `~/.claude/CLAUDE.md`, `~/.claude/codex.md`,
  `~/.claude/DEV_GUIDE.md` — symlinks into `/opt/claude-shared/`. Don't try to
  rewrite them. They'll silently fail (root-owned target).
- Your own `~/.claude/memory/` IS writable — Claude updates it for you.

## 4. Don't read other developers' homes

- `/home/<other-alias>/*` is not yours. Even if filesystem perms accidentally
  allowed it, you must not look. All shell commands are logged.
- Don't `ps`-spy on other devs' processes. `hidepid` is set, but the rule stands
  regardless.

## 5. No secrets in the repo

- `.env*`, private keys (`*.pem`, `id_*`), tokens, passwords — **never commit**.
- The `pre-receive` hook scans for obvious patterns and rejects, but its detection
  is best-effort, not a license. If you accidentally committed a secret, STOP,
  tell the chief immediately.

## 6. Meaningful commit messages

- `feat:` / `fix:` / `refactor:` / `docs:` / `test:` / `chore:` prefix.
- Imperative present, ≤72 chars on the summary line.
- Body explains **why**, not what (the diff already shows what).
- Bad: `fix stuff`, `wip`, `update`, `1`. Good: `fix: trim trailing space in email
  validator before lookup`.

## 7. All shell activity is logged

- Every command you run on this server is captured in audit logs available to
  the chief: `last`, `journalctl _UID=<your-uid>`, shell history,
  `/opt/claude-shared/audit/<YYYY-MM>/<your-alias>.log` (skill invocations).
- This is **for your protection too** — if something blows up, the log proves
  it wasn't you.

## 8. Don't bypass technical limits

- SFTP/SCP/WinSCP are disabled for you on purpose. Don't try to work around it
  (base64 through clipboard, screenshots of code, screen-record). Working
  around limits is treated as a violation of the NDA.
- Use `git push` to ship code. That's the only legitimate channel.

## 9. End every task with `/dev-09-finish`

- When your branch is ready for the chief to merge, run `/dev-09-finish`.
- It will: run pre-deploy checks, run autotests, push the final state, notify
  the chief, and write an audit-log entry.
- Don't try to bypass this. Don't ping the chief in TG asking "merge my branch
  please" — the skill does it correctly with all the metadata.

## 10. Ask when in doubt

- Better to ask one obvious question than to ship code that breaks something.
- The chief prefers a clarifying question over a half-correct guess.

---

## Acceptance

By typing `YES, I AGREE` at the prompt, you confirm:

- You have read all 10 rules.
- You understand that violations may cost you access to the server and to the
  project, and may carry legal consequences under the NDA you also signed.
- Your acceptance is logged with your alias, timestamp, and the hash of this
  file at the moment of acceptance.

Questions go to the chief directly. Don't ask other devs.
