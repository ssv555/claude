#!/usr/bin/env bash
# post-receive — notify mirror daemon that a push has been accepted.
#
# Installed as /srv/git/VDole.git/hooks/post-receive (exec 755).
# Touches /var/spool/vdole-mirror/queue; vdole-mirror.path picks it up.

set -e

QUEUE_FILE='/var/spool/vdole-mirror/queue'

if [ -w "$QUEUE_FILE" ]; then
    # Append pusher + ref info so the queue file mtime always changes
    {
        printf '%s\t%s\t%s\n' "$(date -Is)" "${GIT_PUSHER:-$USER}" "(post-receive)"
    } >> "$QUEUE_FILE" 2>/dev/null || touch "$QUEUE_FILE"
else
    # Best-effort fallback — try touch even if not writable
    touch "$QUEUE_FILE" 2>/dev/null || true
fi

exit 0
