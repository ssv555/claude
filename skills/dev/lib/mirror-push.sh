#!/usr/bin/env bash
# mirror-push.sh — push VDole bare repo to GitHub via bot account.
#
# Triggered by:
#   - systemd vdole-mirror.service (path-unit fires on touch of /var/spool/vdole-mirror/queue)
#   - manual: sudo -u git-mirror /home/git-mirror/bin/mirror-push.sh
#
# Runs as: git-mirror (via sudoers rule for developers, or directly via systemd).

set -euo pipefail

BARE_REPO='/srv/git/VDole.git'
LOG_FILE='/var/log/vdole-mirror.log'

log() { printf '[%(%F %T)T] %s\n' -1 "$*" | tee -a "$LOG_FILE"; }

# Ensure log file writable by git-mirror
if [ ! -w "$LOG_FILE" ] && [ "$(id -u)" -eq 0 ]; then
    touch "$LOG_FILE"
    chown git-mirror:git-mirror "$LOG_FILE"
    chmod 640 "$LOG_FILE"
fi

if [ "$(id -un)" != 'git-mirror' ]; then
    echo "must run as git-mirror (got: $(id -un))" >&2
    exit 1
fi

# Bare is owned root:developers; git-mirror is neither → safe.directory exemption needed
git config --global --add safe.directory "$BARE_REPO" 2>/dev/null || true

cd "$BARE_REPO"

# Remote 'origin' is pre-set during bootstrap (bare config is owned root:developers,
# git-mirror has no write access — see bootstrap-server.sh).
if ! git remote get-url origin >/dev/null 2>&1; then
    log "ERROR: origin remote not configured on bare — ask chief to run /dev bootstrap"
    exit 2
fi

# Push heads + tags explicitly + --prune (deletes branches on origin that no longer
# exist locally). Avoids --mirror which also tries refs/remotes/* / refs/notes/* and
# spams "cannot lock ref refs/remotes/origin/..." warnings on every push (bare has
# no such refs — git --mirror tries to delete them on origin → noise without effect).
ORIGIN_URL=$(git remote get-url origin)
log "pushing heads+tags to $ORIGIN_URL"
attempt=0
max_attempts=3
backoff=2

while : ; do
    attempt=$((attempt + 1))
    if git push --prune origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' 2>&1 | tee -a "$LOG_FILE"; then
        log "push OK (attempt $attempt)"
        exit 0
    fi
    rc=${PIPESTATUS[0]}
    log "push failed (attempt $attempt/$max_attempts, rc=$rc) — see error above"
    if [ "$attempt" -ge "$max_attempts" ]; then
        log "giving up after $max_attempts attempts"
        exit "$rc"
    fi
    sleep "$backoff"
    backoff=$((backoff * 2))
done
