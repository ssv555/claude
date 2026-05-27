#!/usr/bin/env bash
# dev-services-cleanup.sh — kill all dev services listening on per-dev port range
# 40001-49999 (10-port blocks per developer).
#
# Triggered daily at 06:00 by systemd timer dev-services-cleanup.timer.
# Rationale: prevents forgotten `bun run dev` from holding resources
# indefinitely (dev went to bed / vacation / left project).
#
# Does NOT kill dev's SSH sessions, bash, claude — only port-listening services.

set -euo pipefail

LOG='/var/log/dev-services-cleanup.log'

log() { printf '[%(%F %T)T] %s\n' -1 "$*" | tee -a "$LOG"; }

if [ "$EUID" -ne 0 ]; then
    echo "must run as root" >&2
    exit 1
fi

# Find PIDs listening on dev port range
PIDS=$(ss -Hltnp "( sport >= :40001 and sport <= :49999 )" 2>/dev/null \
       | grep -oE 'pid=[0-9]+' | sort -u | cut -d= -f2 || true)

if [ -z "$PIDS" ]; then
    log "no dev services on 40001-49999; nothing to do"
    exit 0
fi

# Safety: only kill processes owned by claude-runner or by users in developers group.
# Anything else on the 4xxxx range is NOT a dev service — skip to avoid clobbering
# chief/system processes that may share the range by accident.
DEV_USERS=$(getent group developers 2>/dev/null | awk -F: '{print $4}' | tr ',' ' ')
ALLOWED="claude-runner $DEV_USERS"

is_allowed() {
    local u="$1"
    for a in $ALLOWED; do [ "$u" = "$a" ] && return 0; done
    return 1
}

KILLED=0
SKIPPED=0
for pid in $PIDS; do
    [ -d "/proc/$pid" ] || continue
    USER_NAME=$(stat -c '%U' "/proc/$pid" 2>/dev/null) || USER_NAME='?'
    CMD=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-120)
    if ! is_allowed "$USER_NAME"; then
        log "SKIP pid=$pid user=$USER_NAME (not in developers or claude-runner) cmd=$CMD"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    log "SIGTERM pid=$pid user=$USER_NAME cmd=$CMD"
    kill -TERM "$pid" 2>/dev/null && KILLED=$((KILLED + 1)) || true
done

# Wait for graceful exit
sleep 5

# Escalate stubborn ones
for pid in $PIDS; do
    if [ -d "/proc/$pid" ]; then
        log "SIGKILL stubborn pid=$pid"
        kill -KILL "$pid" 2>/dev/null || true
    fi
done

log "cleanup done — $KILLED dev process(es) terminated, $SKIPPED skipped (not in developers/claude-runner)"
