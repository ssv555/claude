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
# (other supplementary members still in it). adduser would fail with
# "fatal: The group X already exists".
if getent group "$ALIAS" >/dev/null 2>&1; then
    log "orphaned group $ALIAS detected (no user) — cleaning up"
    gpasswd -d webdev "$ALIAS" 2>/dev/null || true
    gpasswd -d ssv    "$ALIAS" 2>/dev/null || true
    groupdel "$ALIAS" 2>/dev/null || true
fi

# ============================================================================
# 1. Create user + groups
# ============================================================================

log "adduser $ALIAS"
adduser --disabled-password --gecos "$FULL_NAME,,,," "$ALIAS"

usermod -aG developers "$ALIAS"
usermod -aG webdev     "$ALIAS"  # dev needs group:webdev to read /var/lib/webdev/.claude/.credentials.json
usermod -aG "$ALIAS"   ssv       # chief gets read access on dev's HOME without sudo

# HOME root — plain 750 <dev>:<dev>. NO setuid wrapper anymore, NO claude-runner.
# Claude runs as the dev (UID 1002 = spc), so dev itself owns HOME and writes naturally.
# No ACL needed → no sshd StrictModes conflict.
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

# Suppress stock Ubuntu motd banner ("Welcome to Ubuntu 24.04.4 LTS / System info /
# Last login / Documentation links"). /etc/update-motd.d/99-dev-welcome (installed
# by bootstrap-server.sh) renders a compact custom banner instead — alias, repo,
# rules-acceptance, restart-warning, skill shortcuts. ~/.hushlogin is the standard
# Ubuntu mechanism — silences pam_motd's dynamic and static motd output.
# Restart-required line is preserved via our custom motd (reads /var/run/reboot-required).
if [ ! -f "$HOME_DIR/.hushlogin" ]; then
    touch "$HOME_DIR/.hushlogin"
    chown "$ALIAS:$ALIAS" "$HOME_DIR/.hushlogin"
    chmod 644 "$HOME_DIR/.hushlogin"
fi

# Termius default TERM=vt100 breaks Claude TUI (black screen on first run).
# Force xterm-256color + UTF-8 locale for every shell login.
if ! grep -q '^export TERM=xterm-256color' "$HOME_DIR/.bashrc" 2>/dev/null; then
    cat >> "$HOME_DIR/.bashrc" <<'BASHRC_EOF'

# === claude TUI requires modern terminal — Termius default 'vt100' breaks rendering ===
export TERM=xterm-256color
export LC_ALL=en_US.UTF-8
BASHRC_EOF
    chown "$ALIAS:$ALIAS" "$HOME_DIR/.bashrc"
fi

# Auto-cd into the dev's project on interactive SSH login.
# Skipped for non-interactive (scp/sftp/rsync). Idempotent (AUTO_CD_DONE guard
# in the snippet itself, plus grep-marker guard at install-time).
if [ -n "$REPO_NAME" ] && ! grep -q 'AUTO_CD_DONE' "$HOME_DIR/.bashrc" 2>/dev/null; then
    cat >> "$HOME_DIR/.bashrc" <<BASHRC_EOF

# === auto-cd into project on interactive login (skip for scp/sftp) ===
case \$- in *i*)
    if [ -z "\$AUTO_CD_DONE" ] && [ -d "\$HOME/projects/$REPO_NAME" ]; then
        export AUTO_CD_DONE=1
        cd "\$HOME/projects/$REPO_NAME"
    fi
    ;;
esac
BASHRC_EOF
    chown "$ALIAS:$ALIAS" "$HOME_DIR/.bashrc"
fi

# ============================================================================
# 3. ~/.claude/ — owned by the dev (claude runs AS THE DEV, not under setuid).
# ============================================================================

log "scaffolding ~/.claude/ for $ALIAS"
CLAUDE_HOME="$HOME_DIR/.claude"
mkdir -p "$CLAUDE_HOME"

# Read-only chief-managed config: symlinks to /opt/claude-shared/ (root:root 755).
ln -sfn "$SHARED_DIR/skills"     "$CLAUDE_HOME/skills"
ln -sfn "$SHARED_DIR/CLAUDE.md"  "$CLAUDE_HOME/CLAUDE.md"
[ -f "$SHARED_DIR/DEV_GUIDE.md" ]    && ln -sfn "$SHARED_DIR/DEV_GUIDE.md"    "$CLAUDE_HOME/DEV_GUIDE.md"
[ -f "$SHARED_DIR/codex.md" ]        && ln -sfn "$SHARED_DIR/codex.md"        "$CLAUDE_HOME/codex.md"
[ -f "$SHARED_DIR/settings.json" ]   && ln -sfn "$SHARED_DIR/settings.json"   "$CLAUDE_HOME/settings.json"

# Per-dev memory: real directory (NOT symlink). Seeded from chief's curated memory.
mkdir -p "$CLAUDE_HOME/memory"
if [ -d "$SHARED_DIR/memory" ]; then
    cp -a "$SHARED_DIR/memory/." "$CLAUDE_HOME/memory/" 2>/dev/null || true
fi

# Copy webdev's master OAuth credentials into dev's HOME (claude refuses to use
# symlinked or non-owned credentials.json). Each dev gets own copy; refreshes
# diverge over time but bootstrap auth is shared from one Pro/Max login.
WEBDEV_CREDS='/var/lib/webdev/.claude/.credentials.json'
WEBDEV_CONFIG='/var/lib/webdev/.claude.json'
if [ -s "$WEBDEV_CREDS" ]; then
    cp "$WEBDEV_CREDS" "$CLAUDE_HOME/.credentials.json"
    log "copied webdev OAuth creds → $CLAUDE_HOME/.credentials.json"
else
    warn "webdev OAuth creds missing/empty — chief must run: sudo -u webdev -i; claude"
    touch "$CLAUDE_HOME/.credentials.json"
fi
if [ -s "$WEBDEV_CONFIG" ]; then
    cp "$WEBDEV_CONFIG" "$HOME_DIR/.claude.json"
fi

mkdir -p "$CLAUDE_HOME/projects" "$CLAUDE_HOME/sessions"

# Everything in .claude/ owned by the dev (claude runs as them).
chown -R "$ALIAS:$ALIAS" "$CLAUDE_HOME" "$HOME_DIR/.claude.json" 2>/dev/null
chmod 750 "$CLAUDE_HOME"
chmod 700 "$CLAUDE_HOME/memory" "$CLAUDE_HOME/projects" "$CLAUDE_HOME/sessions"
chmod 600 "$CLAUDE_HOME/.credentials.json"
[ -f "$HOME_DIR/.claude.json" ] && chmod 600 "$HOME_DIR/.claude.json"

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

        # Repo owned by dev — claude runs as dev so no extra group/setgid needed.
        REPO_DIR="$HOME_DIR/projects/$REPO_NAME"
        chown -R "$ALIAS:$ALIAS" "$REPO_DIR"

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
        #     Owner: dev. Mode 600. Dev can read (claude runs as dev too).
        #     TODO: build/deploy isolation — split into ~/projects/<repo>/ (dev,
        #     DUMMY) and ~/projects/<repo>-www/ (webdev, REAL) — see docs/todo.
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

            chown "$ALIAS:$ALIAS" "$ENV_OUT"
            chmod 600 "$ENV_OUT"
            log ".env.development written (perms: 600 $ALIAS:$ALIAS — dev reads via claude/bun launched as dev)"
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

# ============================================================================
# 7. README.<ALIAS>.md in dev's HOME — onboarding for the dev (read by them)
# ============================================================================

README_TEMPLATE='/opt/dev-skill/README.template.md'
if [ -f "$README_TEMPLATE" ]; then
    ALIAS_UPPER=$(echo "$ALIAS" | tr '[:lower:]' '[:upper:]')
    README_OUT="$HOME_DIR/README.md"
    log "rendering $README_OUT"

    # Hardcoded server constants (same on all moscow_my dev-stands)
    HOST_IP='195.2.75.212'
    SSH_PORT='53847'

    perl -pe "
        s|\{\{ALIAS\}\}|$ALIAS|g;
        s|\{\{ALIAS_UPPER\}\}|$ALIAS_UPPER|g;
        s|\{\{FULL_NAME\}\}|$FULL_NAME|g;
        s|\{\{EMAIL\}\}|$EMAIL|g;
        s|\{\{HOST_IP\}\}|$HOST_IP|g;
        s|\{\{SSH_PORT\}\}|$SSH_PORT|g;
        s|\{\{PORT_API\}\}|${API_PORT:-NA}|g;
        s|\{\{PORT_HMR\}\}|${HMR_PORT:-NA}|g;
        s|\{\{PORT_BOT_TG\}\}|${TG_BOT_PORT:-NA}|g;
        s|\{\{PORT_BOT_MAX\}\}|${MAX_BOT_PORT:-NA}|g;
        s|\{\{DB_NAME\}\}|${DB_NAME:-NA}|g;
        s|\{\{DB_USER\}\}|${DB_USER:-NA}|g;
        s|\{\{REPO_NAME\}\}|${REPO_NAME:-NA}|g;
    " "$README_TEMPLATE" > "$README_OUT"

    if grep -q '{{' "$README_OUT"; then
        warn "unsubstituted placeholders remaining in $README_OUT:"
        grep -n '{{' "$README_OUT" | head -10 >&2
    fi

    chown "$ALIAS:$ALIAS" "$README_OUT"
    chmod 644 "$README_OUT"
    log "$README_OUT written (dev can read)"
else
    warn "README template not found at $README_TEMPLATE — skip onboarding file"
fi

# ============================================================================
# 8. AGREEMENT.<ALIAS>.md — NDA / confidentiality agreement in dev's HOME
# ============================================================================

AGREEMENT_TEMPLATE='/opt/dev-skill/AGREEMENT.template.md'
if [ -f "$AGREEMENT_TEMPLATE" ]; then
    ALIAS_UPPER=$(echo "$ALIAS" | tr '[:lower:]' '[:upper:]')
    AGREEMENT_OUT="$HOME_DIR/AGREEMENT.md"
    log "rendering $AGREEMENT_OUT"

    # AGREEMENT must NOT leak infrastructure (no IP, no ports, no server paths).
    # Devs on probation see only declarative NDA + their own alias/name/repo.
    perl -pe "
        s|\{\{ALIAS\}\}|$ALIAS|g;
        s|\{\{ALIAS_UPPER\}\}|$ALIAS_UPPER|g;
        s|\{\{FULL_NAME\}\}|$FULL_NAME|g;
        s|\{\{REPO_NAME\}\}|${REPO_NAME:-NA}|g;
    " "$AGREEMENT_TEMPLATE" > "$AGREEMENT_OUT"

    if grep -q '{{' "$AGREEMENT_OUT"; then
        warn "unsubstituted placeholders remaining in $AGREEMENT_OUT:"
        grep -n '{{' "$AGREEMENT_OUT" | head -10 >&2
    fi

    chown "$ALIAS:$ALIAS" "$AGREEMENT_OUT"
    chmod 644 "$AGREEMENT_OUT"
    log "$AGREEMENT_OUT written (dev can read)"
else
    warn "AGREEMENT template not found at $AGREEMENT_TEMPLATE — skip NDA file"
fi

log "dev $ALIAS created"
