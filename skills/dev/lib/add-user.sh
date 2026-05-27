#!/usr/bin/env bash
# add-user.sh — server-side dev user creation.
#
# Args: <alias> <full_name> <email> <pub_key_line> [<repo_name>] [<port_base>]
# Runs as: sudo bash add-user.sh ...

set -euo pipefail

ALIAS="${1:-}"
FULL_NAME="${2:-}"
EMAIL="${3:-}"
PUB_KEY="${4:-}"
REPO_NAME="${5:-}"
PORT_BASE="${6:-}"

SHARED_DIR='/opt/claude-shared'
GIT_BARE_ROOT='/srv/git'

log() { printf '[add-user] %s\n' "$*"; }
warn() { printf '[add-user] WARN: %s\n' "$*" >&2; }
err() { printf '[add-user] ERROR: %s\n' "$*" >&2; }

if [ -z "$ALIAS" ] || [ -z "$FULL_NAME" ] || [ -z "$EMAIL" ] || [ -z "$PUB_KEY" ]; then
    err "usage: add-user.sh <alias> <full_name> <email> <pub_key> [<repo>] [<port_base>]"
    exit 2
fi
if ! [[ "$ALIAS" =~ ^[a-z][a-z0-9_]{2,15}$ ]]; then
    err "invalid alias: $ALIAS"
    exit 2
fi
if [ "$EUID" -ne 0 ]; then
    err "must run as root"
    exit 1
fi

if id -u "$ALIAS" >/dev/null 2>&1; then
    err "user $ALIAS already exists"
    exit 3
fi

# ============================================================================
# 1. Create user + groups
# ============================================================================

log "adduser $ALIAS"
adduser --disabled-password --gecos "$FULL_NAME,,,," "$ALIAS"

usermod -aG developers "$ALIAS"
usermod -aG "$ALIAS"   claude-runner   # claude-runner can read dev's files via group
chmod 750 "/home/$ALIAS"

HOME_DIR="/home/$ALIAS"

# ============================================================================
# 2. ~/.ssh + authorized_keys
# ============================================================================

log "installing authorized_keys"
mkdir -p "$HOME_DIR/.ssh"
echo "$PUB_KEY" > "$HOME_DIR/.ssh/authorized_keys"
chown -R "$ALIAS:$ALIAS" "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"

# ============================================================================
# 3. ~/.claude/ — root-owned top, dev cannot enter (only claude-runner via group)
# ============================================================================

log "scaffolding ~/.claude/ for $ALIAS"
CLAUDE_HOME="$HOME_DIR/.claude"
mkdir -p "$CLAUDE_HOME"
ln -sfn "$SHARED_DIR/skills"     "$CLAUDE_HOME/skills"
ln -sfn "$SHARED_DIR/CLAUDE.md"  "$CLAUDE_HOME/CLAUDE.md"
[ -f "$SHARED_DIR/DEV_GUIDE.md" ] && ln -sfn "$SHARED_DIR/DEV_GUIDE.md" "$CLAUDE_HOME/DEV_GUIDE.md"
[ -f "$SHARED_DIR/codex.md" ]     && ln -sfn "$SHARED_DIR/codex.md"     "$CLAUDE_HOME/codex.md"
if [ -d "$SHARED_DIR/memory" ]; then
    ln -sfn "$SHARED_DIR/memory" "$CLAUDE_HOME/memory"
fi

chown root:claude-runner "$CLAUDE_HOME"
chmod 750 "$CLAUDE_HOME"

for sub in projects sessions; do
    mkdir -p "$CLAUDE_HOME/$sub"
    chown claude-runner:claude-runner "$CLAUDE_HOME/$sub"
    chmod 700 "$CLAUDE_HOME/$sub"
done

touch "$CLAUDE_HOME/.credentials.json"
chown claude-runner:claude-runner "$CLAUDE_HOME/.credentials.json"
chmod 600 "$CLAUDE_HOME/.credentials.json"

# ============================================================================
# 4. ~/projects/ — owned <alias>:<alias> 755
# ============================================================================

mkdir -p "$HOME_DIR/projects"
chown "$ALIAS:$ALIAS" "$HOME_DIR/projects"
chmod 755 "$HOME_DIR/projects"

# ============================================================================
# 5. Git config under dev
# ============================================================================

log "git config for $ALIAS"
sudo -u "$ALIAS" git config --global user.name  "$FULL_NAME"
sudo -u "$ALIAS" git config --global user.email "$EMAIL"
sudo -u "$ALIAS" git config --global init.defaultBranch 'main'
sudo -u "$ALIAS" git config --global pull.rebase 'true'

# ============================================================================
# 6. Optional: clone repo, create per-dev DB, generate .env
# ============================================================================

if [ -n "$REPO_NAME" ]; then
    BARE="$GIT_BARE_ROOT/$REPO_NAME.git"
    if [ ! -d "$BARE" ]; then
        err "bare repo not found: $BARE — skip clone"
    else
        log "cloning $REPO_NAME from $BARE into ~/projects/$REPO_NAME"
        sudo -u "$ALIAS" git config --global --add safe.directory "$BARE"
        sudo -u "$ALIAS" git clone "$BARE" "$HOME_DIR/projects/$REPO_NAME"
        sudo -u "$ALIAS" git -C "$HOME_DIR/projects/$REPO_NAME" config remote.origin.url "$BARE"

        # Plan §1: <dev>:claude-runner 2775 — claude-runner must write into the project
        REPO_DIR="$HOME_DIR/projects/$REPO_NAME"
        chgrp -R claude-runner "$REPO_DIR"
        chmod -R g+w "$REPO_DIR"
        find "$REPO_DIR" -type d -exec chmod g+s {} +

        # ====================================================================
        # 6a. Per-dev port allocation
        # ====================================================================
        if [ -z "$PORT_BASE" ]; then
            # Fallback: try to extract from nginx conf (legacy path; chief should pass explicitly)
            NGINX_CONF="/etc/nginx/conf.d/dev-${ALIAS}.it-joy.ru.conf"
            if [ -f "$NGINX_CONF" ]; then
                PORT_BASE=$(grep -oE 'proxy_pass http://127\.0\.0\.1:[0-9]+' "$NGINX_CONF" | head -1 | grep -oE '[0-9]+$')
            fi
        fi

        if [ -n "$PORT_BASE" ]; then
            API_PORT=$PORT_BASE
            HMR_PORT=$((PORT_BASE + 1))
            TG_BOT_PORT=$((PORT_BASE + 2))
            MAX_BOT_PORT=$((PORT_BASE + 4))
            log "ports for $ALIAS: API=$API_PORT FRONT=$HMR_PORT BOT_TG=$TG_BOT_PORT BOT_MAX=$MAX_BOT_PORT"
        else
            warn "no PORT_BASE supplied and no nginx conf — skipping .env generation"
        fi

        # ====================================================================
        # 6b. Per-dev PostgreSQL: create role + DB cloned from template repo DB
        # ====================================================================
        DB_NAME="${REPO_NAME}_${ALIAS}"
        DB_USER="user_${ALIAS}"
        TEMPLATE_DB="$REPO_NAME"

        if command -v psql >/dev/null 2>&1; then
            # Check template DB exists
            if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$TEMPLATE_DB'" 2>/dev/null | grep -q 1; then
                # Generate random 32-char password
                DB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)

                log "creating PG role $DB_USER + database $DB_NAME (template-cloned from $TEMPLATE_DB)"
                # Create role (with password)
                sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
                    "CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';" >/dev/null

                # Template clone requires no active connections to source. Best-effort.
                sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
                    "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER TEMPLATE $TEMPLATE_DB;" >/dev/null || {
                    warn "template clone failed (likely active connections to $TEMPLATE_DB) — creating empty DB instead"
                    sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
                        "CREATE DATABASE $DB_NAME WITH OWNER $DB_USER;" >/dev/null
                }
                sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
                    "GRANT ALL ON DATABASE $DB_NAME TO $DB_USER;" >/dev/null

                DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
                log "DB ready: $DATABASE_URL"
            else
                warn "template DB '$TEMPLATE_DB' not found in PG — skip per-dev DB creation"
                DATABASE_URL=""
            fi
        else
            warn "psql not on PATH — skip DB creation"
            DATABASE_URL=""
        fi

        # ====================================================================
        # 6c. .env.development — full env with random secrets + per-dev DB
        #     Owner: claude-runner. Mode 600. Dev CANNOT read directly from shell.
        #     Bun reads it only when launched via claude (which runs as claude-runner).
        # ====================================================================
        if [ -n "$PORT_BASE" ]; then
            JWT_SECRET=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64)
            COOKIE_SECRET=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64)
            SESSION_SECRET=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64)

            cat > "$REPO_DIR/.env.development" <<EOF
# Generated by /dev add for $ALIAS on $(date -Iseconds)
# DO NOT EDIT — regenerate via /dev del+add or chief intervention.
# Dev user '$ALIAS' CANNOT read this file (perms 600 claude-runner:claude-runner).
# Bun reads it only when launched via claude CLI (setuid wrapper switches to claude-runner).

NODE_ENV=development

# ===== Ports (must match nginx /etc/nginx/conf.d/dev-${ALIAS}.it-joy.ru.conf) =====
SERVER_PORT=$API_PORT
FRONT_PORT=$HMR_PORT
BOT_TG_PORT=$TG_BOT_PORT
BOT_MAX_PORT=$MAX_BOT_PORT

# ===== Per-dev isolated PostgreSQL =====
DATABASE_URL=${DATABASE_URL:-}

# ===== Random per-dev secrets =====
JWT_SECRET=$JWT_SECRET
COOKIE_SECRET=$COOKIE_SECRET
SESSION_SECRET=$SESSION_SECRET

# ===== Dev URLs =====
PUBLIC_BASE_URL=https://dev-${ALIAS}.it-joy.ru
PUBLIC_API_URL=https://dev-${ALIAS}.it-joy.ru/api

# ===== External services (DUMMY placeholders — features depending on these will not work) =====
# OAuth — chief may inject real test-creds via secure channel if dev needs OAuth testing
GOOGLE_CLIENT_ID=DUMMY_GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=DUMMY_GOOGLE_CLIENT_SECRET
VK_CLIENT_ID=DUMMY_VK_CLIENT_ID
VK_CLIENT_SECRET=DUMMY_VK_CLIENT_SECRET
YANDEX_CLIENT_ID=DUMMY_YANDEX_CLIENT_ID
YANDEX_CLIENT_SECRET=DUMMY_YANDEX_CLIENT_SECRET
MAILRU_CLIENT_ID=DUMMY_MAILRU_CLIENT_ID
MAILRU_CLIENT_SECRET=DUMMY_MAILRU_CLIENT_SECRET

# Telegram / MAX bots — chief provides real test-bot tokens if needed
TG_BOT_TOKEN=DUMMY_TG_BOT_TOKEN
MAX_BOT_TOKEN=DUMMY_MAX_BOT_TOKEN

# SMTP / SMS
SMTP_HOST=DUMMY_SMTP_HOST
SMTP_USER=DUMMY_SMTP_USER
SMTP_PASS=DUMMY_SMTP_PASS
SMS_API_KEY=DUMMY_SMS_API_KEY

# Sentry
SENTRY_DSN=
EOF
            chown claude-runner:claude-runner "$REPO_DIR/.env.development"
            chmod 600 "$REPO_DIR/.env.development"
            log ".env.development written (perms: 600 claude-runner:claude-runner — dev cannot read)"
        fi

        # ====================================================================
        # 6d. bun install (no .env needed for install)
        # ====================================================================
        if [ -f "$REPO_DIR/package.json" ] && command -v bun >/dev/null 2>&1; then
            log "running 'bun install' as $ALIAS"
            sudo -u "$ALIAS" bash -c "cd '$REPO_DIR' && bun install 2>&1 | tail -5" || warn "bun install failed — dev can rerun manually"
        fi
    fi
fi

log "dev $ALIAS created"
