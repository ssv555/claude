#!/usr/bin/env bash
# /usr/local/sbin/dev-accept-rules — privileged helper invoked via sudoers NOPASSWD
# by developers to record their acceptance of /opt/claude-shared/RULES.md.
#
# Trust model:
# - Called as: sudo /usr/local/sbin/dev-accept-rules accept <claimed-hash>
# - sudo sets SUDO_USER to the real invoker; we trust SUDO_USER (cannot be forged
#   when invoked via sudoers, since sudo derives it from the auth chain).
# - We re-compute the hash of /opt/claude-shared/RULES.md HERE — the dev-supplied
#   <claimed-hash> is only echoed back for audit-log consistency; we never trust it.
# - Flag file is written by root (this script's UID), so devs cannot fake one
#   without invoking this script (and every invocation is logged).
# - Script accepts ONLY the `accept` verb with one positional arg. Anything else
#   exits non-zero. Prevents sudoers misuse.

set -euo pipefail

SHARED='/opt/claude-shared'
RULES_FILE="$SHARED/RULES.md"
ACCEPT_DIR="$SHARED/rules_acceptances"
AUDIT_LOG="$SHARED/audit/rules_acceptances.log"

err() { printf '[dev-accept-rules] ERROR: %s\n' "$*" >&2; exit 2; }

VERB="${1:-}"
CLAIMED_HASH="${2:-}"

[ "$VERB" = "accept" ]            || err "verb must be 'accept' (got: $VERB)"
[ "$EUID" -eq 0 ]                  || err "must run as root (via sudoers NOPASSWD)"
[ -n "${SUDO_USER:-}" ]            || err "no SUDO_USER set — must be invoked via sudo"
[ -r "$RULES_FILE" ]               || err "rules file missing: $RULES_FILE"

ALIAS="$SUDO_USER"

# Sanity: alias matches typical dev pattern
if ! printf '%s' "$ALIAS" | grep -qE '^[a-z][a-z0-9_]{2,15}$'; then
    err "invalid SUDO_USER alias: $ALIAS"
fi

# Caller must be in 'developers' group (else this is misuse)
if ! id -nG "$ALIAS" | tr ' ' '\n' | grep -qx developers; then
    err "$ALIAS is not in group 'developers'"
fi

# Compute current rules hash — never trust the one the caller passed
CURRENT_HASH=$(sha256sum "$RULES_FILE" | awk '{print $1}')

# Make dirs (idempotent)
mkdir -p "$ACCEPT_DIR" "$(dirname "$AUDIT_LOG")"
chown root:root "$ACCEPT_DIR" "$(dirname "$AUDIT_LOG")"
chmod 755 "$ACCEPT_DIR"
chmod 750 "$(dirname "$AUDIT_LOG")"

FLAG="$ACCEPT_DIR/${ALIAS}__${CURRENT_HASH}.flag"
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Write flag (root-owned, world-readable for motd check)
{
    printf 'alias=%s\n'      "$ALIAS"
    printf 'rules_hash=%s\n' "$CURRENT_HASH"
    printf 'accepted_at=%s\n' "$TS"
    printf 'client_ip=%s\n'  "${SSH_CLIENT%% *}"
} > "$FLAG"
chown root:root "$FLAG"
chmod 644 "$FLAG"

# Append to audit log (root-only readable)
touch "$AUDIT_LOG"
chown root:root "$AUDIT_LOG"
chmod 600 "$AUDIT_LOG"
printf '%s|%s|%s|%s|claimed_hash=%s\n' \
    "$TS" "$ALIAS" "$CURRENT_HASH" "${SSH_CLIENT%% *}" "$CLAIMED_HASH" \
    >> "$AUDIT_LOG"

printf 'OK %s accepted rules %s at %s\n' "$ALIAS" "$CURRENT_HASH" "$TS"
exit 0
