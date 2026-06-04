#!/usr/bin/env bash
# /usr/local/sbin/dev-notify-start — privileged helper for /dev-00-start.
#
# 1. Append structured line to /opt/claude-shared/audit/started_branches.log
# 2. Send TG via existing amsterdam relay (TOKEN/CHAT_ID from /var/backups/.tg_config)
#
# Usage: sudo /usr/local/sbin/dev-notify-start <branch> <base_sha> <task...>

set -euo pipefail

err() { printf '[dev-notify-start] ERROR: %s\n' "$*" >&2; exit 2; }

[ "$EUID" -eq 0 ]       || err "must run as root (via sudoers NOPASSWD)"
[ -n "${SUDO_USER:-}" ] || err "no SUDO_USER set"

ALIAS="$SUDO_USER"
BRANCH="${1:-}"
BASE_SHA="${2:-}"
shift 2 2>/dev/null || true
TASK="${*:-}"

[ -n "$BRANCH" ]   || err "branch required"
[ -n "$BASE_SHA" ] || err "base_sha required"

sanitize() { printf '%s' "$1" | tr -d '\000-\037|"' | cut -c1-200; }
BRANCH=$(sanitize "$BRANCH")
BASE_SHA=$(sanitize "$BASE_SHA")
TASK=$(sanitize "$TASK")

if ! id -nG "$ALIAS" | tr ' ' '\n' | grep -qx developers; then
    err "$ALIAS is not in developers"
fi

# ============================================================================
# Step 1 — audit log (always; ground truth)
# ============================================================================
SHARED='/opt/claude-shared'
LOG="$SHARED/audit/started_branches.log"
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chown root:root "$LOG"
chmod 640 "$LOG"

printf '%s|%s|%s|%s|%s\n' \
    "$TS" "$ALIAS" "$BRANCH" "$BASE_SHA" "$TASK" \
    >> "$LOG"

# ============================================================================
# Step 2 — TG via existing amsterdam relay
# ============================================================================
TG_CONFIG='/var/backups/.tg_config'
TG_TOKEN=''
TG_CHAT_ID=''

if [ -r "$TG_CONFIG" ]; then
    TG_TOKEN=$(grep -E  '^VDOLE_TELEGRAM_BOT_TOKEN='  "$TG_CONFIG" | cut -d= -f2-)
    TG_CHAT_ID=$(grep -E '^VDOLE_TELEGRAM_USER_ID='   "$TG_CONFIG" | cut -d= -f2-)
    [ -z "$TG_TOKEN" ]   && TG_TOKEN=$(grep   -E '^IAMRICH_TELEGRAM_BOT_TOKEN=' "$TG_CONFIG" | cut -d= -f2-)
    [ -z "$TG_CHAT_ID" ] && TG_CHAT_ID=$(grep -E '^IAMRICH_TELEGRAM_USER_ID='   "$TG_CONFIG" | cut -d= -f2-)
fi

if [ -z "$TG_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    printf 'TG creds missing in %s — log-only (audit OK)\n' "$TG_CONFIG"
    exit 0
fi

BRANCH_SLUG="${BRANCH#dev/}"

# HTML-escape
escape_html() { printf '%s' "$1" | sed -e 's|&|\&amp;|g' -e 's|<|\&lt;|g' -e 's|>|\&gt;|g'; }

H_ALIAS=$(escape_html "$ALIAS")
H_SLUG=$(escape_html "$BRANCH_SLUG")
H_TASK=$(escape_html "$TASK")

# IMPORTANT: literal newlines below — bash $(...) strips trailing \n, would glue lines.
MSG="🚀 <b>${H_ALIAS}</b> начал → <code>${H_SLUG}</code>
base: <code>${BASE_SHA}</code>"

if [ -n "$H_TASK" ]; then
    MSG="${MSG}

<i>${H_TASK}</i>"
fi

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
printf '[dev-notify-start] amsterdam_my failed, trying amsterdam_grey\n' >&2
if relay_via 94.103.80.11 53847; then
    printf 'notified chief via amsterdam_grey\n'
    exit 0
fi

printf '[dev-notify-start] both relays failed — audit log kept, no TG\n' >&2
exit 0
