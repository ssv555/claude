#!/usr/bin/env bash
# /usr/local/sbin/dev-notify-finish — privileged helper for /dev-09-finish.
#
# Two things happen here:
#   1. Append a structured line to /opt/claude-shared/audit/finished_branches.log
#      (chief tails this file).
#   2. Send a TG message to the chief reusing the existing moscow_my relay:
#        TOKEN/CHAT_ID  ← /var/backups/.tg_config (VDOLE_* keys; IAMRICH_* fallback)
#        TG path        ← sudo -u www-data ssh -i /var/www/.ssh/id_backup
#                         amsterdam_my:53847 (fallback amsterdam_grey:53847)
#                       → curl https://api.telegram.org/bot$TOKEN/sendMessage
#      Same mechanism used by /usr/local/bin/vdole-tg-forward.sh and the deploy
#      pipeline's notify_telegram_admin.sh on TST/FBK. No new secrets, no new
#      endpoints, no IP allowlist changes.
#
# If TOKEN/CHAT_ID missing or both relays fail → log-only fallback (no error
# propagation; /dev-09-finish stays green for the dev).
#
# Called via sudoers NOPASSWD by developers.
#
# Usage:  sudo /usr/local/sbin/dev-notify-finish <branch> <head_sha> <commits> <added> <removed> <summary...>

set -euo pipefail

err() { printf '[dev-notify-finish] ERROR: %s\n' "$*" >&2; exit 2; }

[ "$EUID" -eq 0 ]       || err "must run as root (via sudoers NOPASSWD)"
[ -n "${SUDO_USER:-}" ] || err "no SUDO_USER set"

ALIAS="$SUDO_USER"
BRANCH="${1:-}"
HEAD_SHA="${2:-}"
COMMITS="${3:-0}"
ADDED="${4:-0}"
REMOVED="${5:-0}"
shift 5 2>/dev/null || true
SUMMARY="${*:-}"

[ -n "$BRANCH" ]   || err "branch required"
[ -n "$HEAD_SHA" ] || err "head_sha required"

sanitize() { printf '%s' "$1" | tr -d '\000-\037|"' | cut -c1-200; }
BRANCH=$(sanitize "$BRANCH")
HEAD_SHA=$(sanitize "$HEAD_SHA")
SUMMARY=$(sanitize "$SUMMARY")

if ! id -nG "$ALIAS" | tr ' ' '\n' | grep -qx developers; then
    err "$ALIAS is not in developers"
fi

case "$COMMITS$ADDED$REMOVED" in
    *[!0-9]*) err "commits/added/removed must be integers" ;;
esac

# ============================================================================
# Step 1 — audit log (always succeeds; ground truth)
# ============================================================================
SHARED='/opt/claude-shared'
LOG="$SHARED/audit/finished_branches.log"
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chown root:root "$LOG"
chmod 640 "$LOG"

printf '%s|%s|%s|%s|%s|+%s/-%s|%s\n' \
    "$TS" "$ALIAS" "$BRANCH" "$HEAD_SHA" "$COMMITS" "$ADDED" "$REMOVED" "$SUMMARY" \
    >> "$LOG"

# ============================================================================
# Step 2 — TG via existing amsterdam relay
# ============================================================================
TG_CONFIG='/var/backups/.tg_config'
TG_TOKEN=''
TG_CHAT_ID=''

if [ -r "$TG_CONFIG" ]; then
    TG_TOKEN=$(grep -E '^VDOLE_TELEGRAM_BOT_TOKEN=' "$TG_CONFIG" | cut -d= -f2-)
    TG_CHAT_ID=$(grep -E '^VDOLE_TELEGRAM_USER_ID='  "$TG_CONFIG" | cut -d= -f2-)
    # Fallback to IAMRICH keys if VDOLE empty (matches deploy pipeline's discovery order)
    [ -z "$TG_TOKEN" ]   && TG_TOKEN=$(grep   -E '^IAMRICH_TELEGRAM_BOT_TOKEN=' "$TG_CONFIG" | cut -d= -f2-)
    [ -z "$TG_CHAT_ID" ] && TG_CHAT_ID=$(grep -E '^IAMRICH_TELEGRAM_USER_ID='   "$TG_CONFIG" | cut -d= -f2-)
fi

if [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    printf 'TG creds missing in %s — log-only mode (audit OK)\n' "$TG_CONFIG"
    exit 0
fi

# HTML-escape & build message body
escape_html() { printf '%s' "$1" | sed -e 's|&|\&amp;|g' -e 's|<|\&lt;|g' -e 's|>|\&gt;|g'; }
H_ALIAS=$(escape_html "$ALIAS")
H_BRANCH=$(escape_html "$BRANCH")
H_SUMMARY=$(escape_html "$SUMMARY")

MSG=$(printf '✅ <b>dev-branch finished</b>\n<code>%s</code> by <b>%s</b>\nhead: <code>%s</code>\ncommits: %s   diff: +%s/-%s\n\n%s' \
    "$H_BRANCH" "$H_ALIAS" "$HEAD_SHA" "$COMMITS" "$ADDED" "$REMOVED" "$H_SUMMARY")

# Relay via amsterdam — same path as /usr/local/bin/vdole-tg-forward.sh
relay_via() {
    local host="$1" port="$2" code
    code=$(printf '%s' "$MSG" | sudo -u www-data ssh \
        -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        -i /var/www/.ssh/id_backup -p "$port" "www-data@$host" \
        "curl -s --connect-timeout 5 --max-time 10 -X POST \
            'https://api.telegram.org/bot${TG_TOKEN}/sendMessage' \
            --data-urlencode 'chat_id=${TG_CHAT_ID}' \
            --data-urlencode 'parse_mode=HTML' \
            --data-urlencode 'text@-' \
            -o /dev/null -w '%{http_code}'" 2>/dev/null) || code='ssh-failed'
    [ "$code" = "200" ]
}

if relay_via 77.238.231.203 53847; then
    printf 'notified chief via amsterdam_my\n'
    exit 0
fi
printf '[dev-notify-finish] amsterdam_my relay failed, trying amsterdam_grey\n' >&2

if relay_via 94.103.80.11 53847; then
    printf 'notified chief via amsterdam_grey\n'
    exit 0
fi

printf '[dev-notify-finish] both relays failed — audit log kept, no TG\n' >&2
exit 0
