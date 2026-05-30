#!/usr/bin/env bash
# /usr/local/sbin/dev-notify-finish — privileged helper for /dev-09-finish.
#
# Two things happen here:
#   1. Append a structured line to /opt/claude-shared/audit/finished_branches.log
#      (chief tails this file).
#   2. If /opt/dev-skill/notify.conf exists with WEBHOOK_URL + WEBHOOK_SECRET,
#      POST a JSON payload to that URL (chief's TG notifier endpoint).
#      Missing config → log-only mode (no error).
#
# Called via sudoers NOPASSWD by developers.
#
# Usage:  sudo /usr/local/sbin/dev-notify-finish <branch> <head_sha> <commits> <added> <removed> <summary...>

set -euo pipefail

err() { printf '[dev-notify-finish] ERROR: %s\n' "$*" >&2; exit 2; }

[ "$EUID" -eq 0 ]                 || err "must run as root (via sudoers NOPASSWD)"
[ -n "${SUDO_USER:-}" ]           || err "no SUDO_USER set"

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

# Numeric sanity
case "$COMMITS$ADDED$REMOVED" in
    *[!0-9]*) err "commits/added/removed must be integers" ;;
esac

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

# Optional webhook notification — config at /opt/dev-skill/notify.conf:
#   WEBHOOK_URL=https://vdole.it-joy.ru/api/_internal/alert
#   WEBHOOK_SECRET=<shared HMAC secret>
CONF='/opt/dev-skill/notify.conf'
if [ -r "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
    if [ -n "${WEBHOOK_URL:-}" ] && [ -n "${WEBHOOK_SECRET:-}" ] && command -v curl >/dev/null 2>&1; then
        PAYLOAD=$(printf '{"type":"dev_finished","alias":"%s","branch":"%s","head":"%s","commits":%s,"added":%s,"removed":%s,"summary":"%s","ts":"%s"}' \
            "$ALIAS" "$BRANCH" "$HEAD_SHA" "$COMMITS" "$ADDED" "$REMOVED" "$SUMMARY" "$TS")

        # HMAC-SHA256 signature header (consumer verifies)
        SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex 2>/dev/null | awk '{print $NF}')

        # Retry 3x with backoff (network resiliency)
        for attempt in 1 2 3; do
            HTTP_CODE=$(curl -sS --max-time 8 -o /tmp/dev-notify.body \
                -w '%{http_code}' \
                -H 'Content-Type: application/json' \
                -H "X-Signature: sha256=$SIG" \
                -X POST -d "$PAYLOAD" \
                "$WEBHOOK_URL" 2>/dev/null || echo '000')
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
                rm -f /tmp/dev-notify.body
                printf 'notified chief (HTTP %s)\n' "$HTTP_CODE"
                exit 0
            fi
            printf '[dev-notify-finish] attempt %d/3 failed (HTTP %s)\n' "$attempt" "$HTTP_CODE" >&2
            [ -f /tmp/dev-notify.body ] && head -c 200 /tmp/dev-notify.body >&2 && printf '\n' >&2
            sleep $((attempt * 2))
        done

        printf '[dev-notify-finish] webhook delivery failed after 3 attempts — log-only fallback\n' >&2
        rm -f /tmp/dev-notify.body
    fi
fi

printf 'logged to %s\n' "$LOG"
exit 0
