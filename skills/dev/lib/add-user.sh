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

# Orphan group cleanup: previous /dev del may have left group $ALIAS alive
# (claude-runner still in it as supplementary member). adduser would fail with
# "fatal: The group X already exists".
if getent group "$ALIAS" >/dev/null 2>&1; then
    log "orphaned group $ALIAS detected (no user) — cleaning up"
    gpasswd -d claude-runner "$ALIAS" 2>/dev/null || true
    groupdel "$ALIAS" 2>/dev/null || true
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
# 3. ~/.claude/ — owned by claude-runner so claude can fully manage its own
#    workspace (create settings.json, hooks, write to memory, etc.).
#    Dev (spc) is NOT in group claude-runner → falls into 'other' class → 0 perms → denied.
# ============================================================================

log "scaffolding ~/.claude/ for $ALIAS"
CLAUDE_HOME="$HOME_DIR/.claude"
mkdir -p "$CLAUDE_HOME"

# Read-only chief-managed config: symlinks to /opt/claude-shared/ (root:root 755).
# Devs and their claude cannot modify these — central rules of conduct.
ln -sfn "$SHARED_DIR/skills"     "$CLAUDE_HOME/skills"
ln -sfn "$SHARED_DIR/CLAUDE.md"  "$CLAUDE_HOME/CLAUDE.md"
[ -f "$SHARED_DIR/DEV_GUIDE.md" ] && ln -sfn "$SHARED_DIR/DEV_GUIDE.md" "$CLAUDE_HOME/DEV_GUIDE.md"
[ -f "$SHARED_DIR/codex.md" ]     && ln -sfn "$SHARED_DIR/codex.md"     "$CLAUDE_HOME/codex.md"

# Per-dev memory: real directory (NOT symlink) so claude can update it freely.
# Seeded once from chief's curated memory; from then on each dev's memory diverges.
mkdir -p "$CLAUDE_HOME/memory"
if [ -d "$SHARED_DIR/memory" ]; then
    cp -a "$SHARED_DIR/memory/." "$CLAUDE_HOME/memory/" 2>/dev/null || true
fi

# claude-runner is owner of .claude/ top-level — can create settings.json, hooks, etc.
chown -R claude-runner:claude-runner "$CLAUDE_HOME"
chmod 750 "$CLAUDE_HOME"
chmod 700 "$CLAUDE_HOME/memory"

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
    # Case-insensitive lookup: dev.ps1 lowercases repo arg, but bare repo on disk
    # may be CamelCase (e.g. /srv/git/VDole.git). Match by -iname.
    BARE=$(find "$GIT_BARE_ROOT" -maxdepth 1 -type d -iname "${REPO_NAME}.git" 2>/dev/null | head -1)
    if [ -z "$BARE" ] || [ ! -d "$BARE" ]; then
        err "bare repo not found: $GIT_BARE_ROOT/${REPO_NAME}.git (case-insensitive) — skip clone"
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
                # Generate random 32-char password (hex). Use openssl to avoid
                # `tr | head` SIGPIPE under `set -euo pipefail` (exit 141).
                DB_PASS=$(openssl rand -hex 16)

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
        # 6c. .env.development — render from /opt/dev-skill/.env.outstaffers
        #     template (uploaded by dev.ps1 from chief PC). Substitutes placeholders
        #     with per-dev values, then writes to $REPO_DIR/.env.development.
        #     Owner: claude-runner. Mode 600. Dev CANNOT read directly from shell.
        #     Bun reads it only when launched via claude (which runs as claude-runner).
        # ====================================================================
        ENV_TEMPLATE='/opt/dev-skill/.env.development'
        if [ -n "$PORT_BASE" ] && [ -f "$ENV_TEMPLATE" ]; then
            # openssl rand -hex 32 → 64 hex chars (256 bits). Avoids `tr|head` SIGPIPE under pipefail.
            JWT_SECRET=$(openssl rand -hex 32)
            COOKIE_SECRET=$(openssl rand -hex 32)
            SESSION_SECRET=$(openssl rand -hex 32)
            BOT_SECRET=$(openssl rand -hex 32)
            DATA_ENCRYPTION_KEY=$(openssl rand -hex 32)
            EMAIL_WEBHOOK_SECRET=$(openssl rand -hex 32)
            # DB_PASS already generated in step 6b above

            ENV_OUT="$REPO_DIR/.env.development"
            log "rendering .env.development from $ENV_TEMPLATE"

            # Substitute placeholders. Use perl for safe in-place replacement
            # (sed would need escaping for /, &, etc. in random secrets).
            perl -pe "
                s|\{\{ALIAS\}\}|$ALIAS|g;
                s|\{\{PORT_API\}\}|$API_PORT|g;
                s|\{\{PORT_HMR\}\}|$HMR_PORT|g;
                s|\{\{PORT_BOT_TG\}\}|$TG_BOT_PORT|g;
                s|\{\{PORT_BOT_MAX\}\}|$MAX_BOT_PORT|g;
                s|\{\{DB_PASSWORD\}\}|$DB_PASS|g;
                s|\{\{JWT_SECRET\}\}|$JWT_SECRET|g;
                s|\{\{COOKIE_SECRET\}\}|$COOKIE_SECRET|g;
                s|\{\{SESSION_SECRET\}\}|$SESSION_SECRET|g;
                s|\{\{BOT_SECRET\}\}|$BOT_SECRET|g;
                s|\{\{DATA_ENCRYPTION_KEY\}\}|$DATA_ENCRYPTION_KEY|g;
                s|\{\{EMAIL_WEBHOOK_SECRET\}\}|$EMAIL_WEBHOOK_SECRET|g;
            " "$ENV_TEMPLATE" > "$ENV_OUT"

            # Sanity check: any unsubstituted {{}} placeholder = bug
            if grep -q '{{' "$ENV_OUT"; then
                warn "unsubstituted placeholders remaining in $ENV_OUT:"
                grep -n '{{' "$ENV_OUT" | head -10 >&2
            fi

            chown claude-runner:claude-runner "$ENV_OUT"
            chmod 600 "$ENV_OUT"
            log ".env.development written (perms: 600 claude-runner:claude-runner — dev cannot read)"
        elif [ ! -f "$ENV_TEMPLATE" ]; then
            err "env template not found at $ENV_TEMPLATE — chief must run /dev add from PC where .env.outstaffers exists"
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
