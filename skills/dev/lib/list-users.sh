#!/usr/bin/env bash
# list-users.sh — emit JSON array of all dev users in the 'developers' group.
#
# Optional arg: filter to a single alias.

set -euo pipefail

FILTER="${1:-}"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: must run as root" >&2
    exit 1
fi

# If developers group doesn't exist yet — nothing to list
if ! getent group developers &>/dev/null; then
    printf '[]\n'
    exit 0
fi

# Get all users in 'developers' group (primary or supplementary)
get_dev_users() {
    local dev_members
    dev_members="$(getent group developers | awk -F: '{print $4}' | tr ',' '\n' | sort -u || true)"
    # Also catch users with primary GID = developers (rare)
    local dev_gid
    dev_gid="$(getent group developers | awk -F: '{print $3}' || true)"
    local primary_users
    primary_users="$(awk -F: -v g="$dev_gid" '$4==g {print $1}' /etc/passwd || true)"
    printf '%s\n%s\n' "$dev_members" "$primary_users" | grep -v '^$' | sort -u || true
}

dev_users="$(get_dev_users)"
if [ -n "$FILTER" ]; then
    dev_users="$(printf '%s\n' "$dev_users" | grep -Fx "$FILTER" || true)"
fi

# Build JSON
printf '['
first=1
while IFS= read -r u; do
    [ -z "$u" ] && continue
    [ "$u" = "claude-runner" ] && continue
    [ "$u" = "git-mirror" ] && continue
    [ "$u" = "ssv" ] && continue

    HOME_DIR="$(getent passwd "$u" | awk -F: '{print $6}')"
    [ -z "$HOME_DIR" ] && continue
    [ ! -d "$HOME_DIR" ] && continue

    CREATED_AT="$(stat -c '%y' "$HOME_DIR" 2>/dev/null | cut -d. -f1 | tr ' ' 'T' || echo '')"

    # Last login (from `last`)
    LAST_LOGIN="$(last -n 1 "$u" 2>/dev/null | awk 'NR==1 && NF>3 { for(i=4;i<=8;i++) printf "%s ", $i; print "" }' | sed 's/[[:space:]]*$//' || echo '')"
    # Last git commit anywhere under home
    LAST_COMMIT="$(find "$HOME_DIR/projects" -maxdepth 3 -name '.git' -type d 2>/dev/null | head -20 | while read -r g; do
        git --git-dir="$g" log -1 --pretty=format:'%cI' 2>/dev/null || true
    done | sort | tail -1)"

    # Use whichever is most recent as last_activity (ISO 8601 preferred)
    LAST_ACTIVITY="${LAST_COMMIT:-$CREATED_AT}"

    SESSION_COUNT="$(find "$HOME_DIR/.claude/projects" -maxdepth 3 -name '*.jsonl' 2>/dev/null | wc -l)"
    HOME_BYTES="$(du -sb "$HOME_DIR" 2>/dev/null | awk '{print $1}' || echo 0)"

    [ $first -eq 1 ] && first=0 || printf ','
    printf '{"alias":"%s","created_at":"%s","last_activity":"%s","session_count":%s,"home_bytes":%s}' \
        "$u" "$CREATED_AT" "$LAST_ACTIVITY" "$SESSION_COUNT" "$HOME_BYTES"
done <<< "$dev_users"
printf ']\n'
