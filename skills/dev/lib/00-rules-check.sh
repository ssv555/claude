#!/usr/bin/env bash
# /etc/profile.d/00-rules-check.sh — RULES acceptance gate.
#
# On every interactive shell login for users in group 'developers':
# - Compute SHA-256 of /opt/claude-shared/RULES.md.
# - If /opt/claude-shared/rules_acceptances/<user>__<hash>.flag exists → pass.
# - Else: display RULES via less, prompt for `YES, I AGREE`, on match invoke
#   `sudo /usr/local/sbin/dev-accept-rules accept <hash>` (sudoers NOPASSWD).
#   On mismatch: log the user out (`exit 1` in a profile.d script kicks them out
#   because /etc/profile is sourced as login shell init).
#
# Non-interactive shells (scp/sftp/rsync/git push over ssh) skip the gate.

# Guard: interactive only. profile.d runs for every login shell but we want to
# allow non-interactive ssh "command" invocations (e.g. git push uses ssh+shell
# to invoke git-receive-pack but is non-interactive). PS1 is set only when
# interactive; $- contains 'i' for interactive shells.
case $- in
    *i*) ;;
    *)   return 0 2>/dev/null || exit 0 ;;
esac

# Skip for non-developers (chief, system users — they have their own setup)
if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx developers; then
    return 0 2>/dev/null || exit 0
fi

SHARED='/opt/claude-shared'
RULES_FILE="$SHARED/RULES.md"
ACCEPT_DIR="$SHARED/rules_acceptances"

# If rules file missing, fail-open with a warning (better than locking devs out
# of a broken bootstrap)
if [ ! -r "$RULES_FILE" ]; then
    printf '\033[33m[rules-gate] %s missing — gate disabled (warn chief)\033[0m\n' "$RULES_FILE" >&2
    return 0 2>/dev/null || exit 0
fi

CURRENT_HASH=$(sha256sum "$RULES_FILE" 2>/dev/null | awk '{print $1}')
if [ -z "$CURRENT_HASH" ]; then
    printf '\033[33m[rules-gate] cannot hash RULES.md — gate disabled\033[0m\n' >&2
    return 0 2>/dev/null || exit 0
fi

FLAG="$ACCEPT_DIR/${USER}__${CURRENT_HASH}.flag"

if [ -r "$FLAG" ]; then
    # Already accepted current version — silent pass
    return 0 2>/dev/null || exit 0
fi

# Not accepted — show rules + prompt
cat <<EOF


====================================================================
  ТРЕБУЕТСЯ ПРИНЯТИЕ ПРАВИЛ  /  RULES ACCEPTANCE REQUIRED
====================================================================
  🇷🇺 Прочти правила. Нажми ENTER — откроется пейджер (less, выход — q).
      После закрытия пейджера введи фразу принятия точно как написано.
      Чтобы отказаться — введи NO или просто Enter, тебя залогаутит.

  🇬🇧 Read the rules. Press ENTER — opens in pager (less, q to quit).
      After the pager closes, type the acceptance phrase exactly.
      To decline — type NO or just press Enter; you'll be logged out.
====================================================================

EOF

# Wait for ENTER before showing pager
read -r _ < /dev/tty || {
    printf '\n[rules-gate] no tty — cannot prompt. Aborting login.\n' >&2
    exit 1
}

# Show rules via less
less -RX "$RULES_FILE" < /dev/tty > /dev/tty || true

# Prompt for acceptance — bilingual + explicit decline
printf '\n'
printf '────────────────────────────────────────────────────────────────────\n'
printf '🇷🇺 Принять:  введи  \033[1mYES, I AGREE\033[0m  и нажми Enter.\n'
printf '   Отказаться: введи  \033[1mNO\033[0m  (или просто Enter) — залогаутит.\n'
printf '🇬🇧 Accept:   type  \033[1mYES, I AGREE\033[0m  and press Enter.\n'
printf '   Decline:  type  \033[1mNO\033[0m  (or just Enter) — logs you out.\n'
printf '────────────────────────────────────────────────────────────────────\n'
printf '> '

REPLY=''
read -r REPLY < /dev/tty || REPLY=''

if [ "$REPLY" != "YES, I AGREE" ]; then
    case "$REPLY" in
        NO|no|No|'') printf '\n[rules-gate] не принято / not accepted — logging out.\n' ;;
        *)           printf '\n[rules-gate] фраза не совпала / phrase mismatch — logging out.\n' ;;
    esac
    sleep 1
    # profile.d runs sourced inside the login shell — `exit` here exits the shell
    # and ssh closes the session.
    exit 1
fi

# Invoke privileged helper to record acceptance
if sudo -n /usr/local/sbin/dev-accept-rules accept "$CURRENT_HASH" < /dev/tty > /dev/tty; then
    printf '\n\033[32m[rules-gate] acceptance recorded. Welcome, %s.\033[0m\n\n' "$USER"
    sleep 1
else
    printf '\n\033[31m[rules-gate] helper failed — contact chief.\033[0m\n' >&2
    sleep 1
    exit 1
fi
