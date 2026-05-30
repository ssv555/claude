#!/usr/bin/env bash
# /usr/local/sbin/dev-audit-log — privileged append-only logger for /dev-NN-* skills.
# Called via sudoers NOPASSWD by developers. Caller cannot forge entries from
# another alias (SUDO_USER is trusted), cannot read existing logs (root-only
# permissions on the audit directory), and cannot tamper with prior entries.
#
# Usage:  sudo /usr/local/sbin/dev-audit-log <skill> <branch> <summary...>
#
#   <skill>   one of: dev-00-start dev-01-status dev-05-commit dev-07-commit-push
#                     dev-08-reset dev-09-finish
#   <branch>  git branch name (free-form, sanitized; <=120 chars)
#   <summary> remainder is joined and trimmed to 200 chars
#
# Log lines: ISO8601|alias|skill|branch|client_ip|summary
# Files:     /opt/claude-shared/audit/<YYYY-MM>/<alias>.log (mode 600 root:root)

set -euo pipefail

err() { printf '[dev-audit-log] ERROR: %s\n' "$*" >&2; exit 2; }

[ "$EUID" -eq 0 ]                 || err "must run as root (via sudoers NOPASSWD)"
[ -n "${SUDO_USER:-}" ]           || err "no SUDO_USER set"

ALIAS="$SUDO_USER"
SKILL="${1:-}"
BRANCH="${2:-}"
shift 2 2>/dev/null || true
SUMMARY="${*:-}"

# Validate inputs (defense against sudoers misuse / log-poisoning attempts)
case "$SKILL" in
    dev-00-start|dev-01-status|dev-05-commit|dev-07-commit-push|dev-08-reset|dev-09-finish) ;;
    *) err "unknown skill: $SKILL" ;;
esac

# Strip control chars / pipes / newlines from free-form fields
sanitize() { printf '%s' "$1" | tr -d '\000-\037|' | cut -c1-200; }
BRANCH=$(sanitize "$BRANCH")
SUMMARY=$(sanitize "$SUMMARY")

# Verify caller is in developers group
if ! id -nG "$ALIAS" | tr ' ' '\n' | grep -qx developers; then
    err "$ALIAS is not in developers"
fi

SHARED='/opt/claude-shared'
YEAR_MONTH=$(date -u '+%Y-%m')
LOG_DIR="$SHARED/audit/$YEAR_MONTH"
LOG_FILE="$LOG_DIR/$ALIAS.log"

mkdir -p "$LOG_DIR"
chown root:root "$LOG_DIR"
chmod 750 "$LOG_DIR"

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
IP="${SSH_CLIENT%% *}"
[ -z "$IP" ] && IP='-'

# Append-only write
touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 600 "$LOG_FILE"
printf '%s|%s|%s|%s|%s|%s\n' "$TS" "$ALIAS" "$SKILL" "$BRANCH" "$IP" "$SUMMARY" >> "$LOG_FILE"

exit 0
