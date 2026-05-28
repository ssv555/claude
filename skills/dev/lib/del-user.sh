#!/usr/bin/env bash
# del-user.sh — server-side dev user deletion with archive.
#
# Args: <alias> <date>
# Leaves archives in /tmp/dev-del-<alias>-<date>/ for the caller to scp back.

set -euo pipefail

ALIAS="${1:-}"
DATE="${2:-$(date +%F)}"

log() { printf '[del-user] %s\n' "$*"; }
err() { printf '[del-user] ERROR: %s\n' "$*" >&2; }

if [ -z "$ALIAS" ]; then
    err "usage: del-user.sh <alias> [<date>]"
    exit 2
fi
if [ "$EUID" -ne 0 ]; then
    err "must run as root"
    exit 1
fi
if ! id -u "$ALIAS" >/dev/null 2>&1; then
    err "user $ALIAS does not exist"
    exit 3
fi
if [ "$ALIAS" = "root" ] || [ "$ALIAS" = "ssv" ] || [ "$ALIAS" = "claude-runner" ] || [ "$ALIAS" = "git-mirror" ]; then
    err "refusing to delete protected user $ALIAS"
    exit 4
fi

HOME_DIR="/home/$ALIAS"
ARCHIVE_DIR="/tmp/dev-del-$ALIAS-$DATE"

log "killing processes of $ALIAS"
pkill -KILL -u "$ALIAS" 2>/dev/null || true
sleep 1
pkill -KILL -u "$ALIAS" 2>/dev/null || true

mkdir -p "$ARCHIVE_DIR"
chmod 700 "$ARCHIVE_DIR"

# 1. claude projects
if [ -d "$HOME_DIR/.claude/projects" ]; then
    log "archiving .claude/projects/"
    tar -C "$HOME_DIR/.claude" -czf "$ARCHIVE_DIR/claude-projects.tar.gz" projects 2>/dev/null || true
fi

# 2. claude sessions
if [ -d "$HOME_DIR/.claude/sessions" ]; then
    log "archiving .claude/sessions/"
    tar -C "$HOME_DIR/.claude" -czf "$ARCHIVE_DIR/claude-sessions.tar.gz" sessions 2>/dev/null || true
fi

# 3. repos under ~/projects/ — exclude build outputs
EXCLUDES=(
    --exclude='node_modules'
    --exclude='.next'
    --exclude='dist'
    --exclude='build'
    --exclude='.cache'
    --exclude='.turbo'
    --exclude='.vite'
    --exclude='target'
    --exclude='out'
    --exclude='__pycache__'
    --exclude='.pytest_cache'
)
if [ -d "$HOME_DIR/projects" ]; then
    log "archiving projects/ (excluding build outputs)"
    tar -C "$HOME_DIR" "${EXCLUDES[@]}" -czf "$ARCHIVE_DIR/projects.tar.gz" projects 2>/dev/null || true
fi

# 4. rest of home (excluding the above)
log "archiving rest of home"
tar -C /home \
    --exclude="$ALIAS/.claude/projects" \
    --exclude="$ALIAS/.claude/sessions" \
    --exclude="$ALIAS/projects" \
    --exclude="$ALIAS/.cache" \
    -czf "$ARCHIVE_DIR/home.tar.gz" "$ALIAS" 2>/dev/null || true

# 5. activity dump
log "dumping activity log"
{
    echo "=== last $ALIAS | head -200 ==="
    last "$ALIAS" 2>/dev/null | head -200 || true
    echo
    echo "=== journalctl _UID=$(id -u "$ALIAS") --since=-90days (last 500 lines) ==="
    journalctl _UID="$(id -u "$ALIAS")" --since=-90days 2>/dev/null | tail -500 || true
} > "$ARCHIVE_DIR/activity.txt"

# 6. summary
log "archive contents:"
ls -lh "$ARCHIVE_DIR/"

# 7. PostgreSQL — backup (pg_dump) BEFORE drop, then drop role+DBs
DB_USER="user_${ALIAS}"
if command -v psql >/dev/null 2>&1 && command -v pg_dump >/dev/null 2>&1; then
    # 7a. pg_dump every DB owned by the role into archive (gzipped custom format)
    log "pg_dump-ing databases owned by $DB_USER into archive"
    sudo -u postgres psql -tAc \
        "SELECT datname FROM pg_database WHERE pg_catalog.pg_get_userbyid(datdba)='$DB_USER';" 2>/dev/null | while read -r db; do
        [ -n "$db" ] || continue
        DUMP_FILE="$ARCHIVE_DIR/pgdump_${db}.dump"
        log "  dumping $db -> $(basename "$DUMP_FILE")"
        if sudo -u postgres pg_dump -Fc -f "$DUMP_FILE" "$db" 2>>"$ARCHIVE_DIR/pgdump.log"; then
            log "    OK ($(du -h "$DUMP_FILE" | cut -f1))"
        else
            err "    pg_dump $db failed (see $ARCHIVE_DIR/pgdump.log) — continuing"
        fi
    done

    # 7b. Drop databases (with active-connection termination)
    log "dropping PG databases owned by $DB_USER"
    sudo -u postgres psql -tAc \
        "SELECT datname FROM pg_database WHERE pg_catalog.pg_get_userbyid(datdba)='$DB_USER';" 2>/dev/null | while read -r db; do
        [ -n "$db" ] || continue
        log "  dropping DB $db"
        sudo -u postgres psql -c "REVOKE CONNECT ON DATABASE \"$db\" FROM PUBLIC;" >/dev/null 2>&1 || true
        sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db';" >/dev/null 2>&1 || true
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$db\";" >/dev/null 2>&1 || true
    done

    # 7c. Drop role
    log "dropping PG role $DB_USER"
    sudo -u postgres psql -c "DROP ROLE IF EXISTS \"$DB_USER\";" >/dev/null 2>&1 || true
fi

# 8. userdel -r
log "userdel -r $ALIAS"
userdel -r "$ALIAS" 2>&1 || {
    err "userdel failed, possibly residual processes — retrying"
    pkill -KILL -u "$ALIAS" 2>/dev/null || true
    sleep 2
    userdel -r "$ALIAS"
}

# Remove from claude-runner's supplementary groups (group itself was wiped by userdel)
log "user $ALIAS deleted; archives at $ARCHIVE_DIR/"
