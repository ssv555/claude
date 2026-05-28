#!/usr/bin/env bash
# bootstrap-server.sh — idempotent server bootstrap for /dev skill.
#
# Creates system users, shared claude env, setuid wrapper, bare VDole repo,
# git-mirror daemon. Each step checks and skips if already done.
#
# Run as: sudo bash bootstrap-server.sh
# Marker on success: /opt/dev-skill/.bootstrap-ok

set -euo pipefail

SKILL_DIR='/opt/dev-skill'
SHARED_DIR='/opt/claude-shared'
CLAUDE_BIN_DIR='/opt/claude'
WRAPPER_PATH='/usr/local/bin/claude'
BARE_REPO='/srv/git/VDole.git'
MIRROR_HOME='/home/git-mirror'
MIRROR_QUEUE_DIR='/var/spool/vdole-mirror'

log()  { printf '[bootstrap] %s\n' "$*"; }
warn() { printf '[bootstrap] WARN: %s\n' "$*" >&2; }
err()  { printf '[bootstrap] ERROR: %s\n' "$*" >&2; }

if [ "$EUID" -ne 0 ]; then
    err "must run as root (sudo)"
    exit 1
fi

# ============================================================================
# 1. System users
# ============================================================================

ensure_system_user() {
    local name="$1"
    local home="$2"
    if id -u "$name" >/dev/null 2>&1; then
        log "user '$name' exists"
        return 0
    fi
    log "creating system user '$name' (home=$home)"
    useradd --system --create-home --home-dir "$home" --shell /usr/sbin/nologin "$name"
}

ensure_group() {
    local name="$1"
    if getent group "$name" >/dev/null 2>&1; then
        log "group '$name' exists"
        return 0
    fi
    log "creating group '$name'"
    groupadd "$name"
}

ensure_system_user 'claude-runner' '/var/lib/claude-runner'
ensure_system_user 'git-mirror'    "$MIRROR_HOME"
ensure_group 'developers'

# ============================================================================
# 1a. Filesystem isolation — devs see only their own work + claude shared
# ============================================================================
# Ensure acl tools installed
if ! command -v setfacl >/dev/null 2>&1; then
    log "installing acl package"
    DEBIAN_FRONTEND=noninteractive apt-get install -y acl >/dev/null 2>&1 || warn "apt install acl failed"
fi

if command -v setfacl >/dev/null 2>&1; then
    # Strip world-write on /var/www if 777
    if [ -d /var/www ] && [ "$(stat -c '%a' /var/www)" = "777" ]; then
        log "fixing /var/www 777 -> 755"
        chmod 755 /var/www
    fi

    # Full block (---): dev cannot enter or list these
    for p in /var /backup /lost+found /snap /media /mnt /cdrom \
             /opt/certbot /opt/containerd /opt/dev-skill /opt/qdrant; do
        [ -e "$p" ] && setfacl -m g:developers:--- "$p" 2>/dev/null || true
    done

    # Traverse-only (--x): dev cd's to known subdirs but can't ls parent
    for p in /home /opt /srv /srv/git; do
        [ -e "$p" ] && setfacl -m g:developers:--x "$p" 2>/dev/null || true
    done

    log "filesystem isolation ACLs applied"
fi

# ============================================================================
# 1b. sshd AllowGroups — make sure 'developers' group is allowed
# ============================================================================
# If hardening uses 'AllowUsers' that doesn't include developers — we cannot SSH
# in as dev. If 'AllowGroups' is used — append 'developers' if missing.
HARDENING='/etc/ssh/sshd_config.d/01-hardening.conf'
if [ -f "$HARDENING" ]; then
    if grep -qE '^AllowGroups' "$HARDENING"; then
        if ! grep -qE '^AllowGroups[[:space:]].*\bdevelopers\b' "$HARDENING"; then
            log "appending 'developers' to AllowGroups in $HARDENING"
            sed -i 's|^\(AllowGroups[[:space:]].*\)$|\1 developers|' "$HARDENING"
            sshd -t && systemctl reload ssh && log "sshd reloaded"
        fi
    else
        warn "sshd hardening file has no AllowGroups directive — devs may be blocked. Check $HARDENING manually."
    fi
fi

# ============================================================================
# 2. claude CLI — install into /opt/claude/ (isolated bun prefix)
# ============================================================================

if [ ! -x "$CLAUDE_BIN_DIR/bin/claude" ]; then
    log "installing claude CLI to $CLAUDE_BIN_DIR/"
    mkdir -p "$CLAUDE_BIN_DIR"
    if command -v bun >/dev/null 2>&1; then
        BUN_INSTALL="$CLAUDE_BIN_DIR" bun add -g @anthropic-ai/claude-code || {
            warn "bun install failed — falling back to npm"
            if command -v npm >/dev/null 2>&1; then
                npm install --prefix "$CLAUDE_BIN_DIR" -g @anthropic-ai/claude-code
            else
                err "neither bun nor npm available — install one of them and rerun"
                exit 1
            fi
        }
    elif command -v npm >/dev/null 2>&1; then
        npm install --prefix "$CLAUDE_BIN_DIR" -g @anthropic-ai/claude-code
    else
        err "neither bun nor npm available — install one of them and rerun"
        exit 1
    fi
    chown -R root:root "$CLAUDE_BIN_DIR"
else
    log "claude CLI already at $CLAUDE_BIN_DIR/"
fi

# ============================================================================
# 3. /opt/claude-shared/ — shared config skeleton
# ============================================================================

log "ensuring $SHARED_DIR/ skeleton"
mkdir -p "$SHARED_DIR/skills" "$SHARED_DIR/memory"

# Install dev-version CLAUDE.md (always overwrite — chief manages content)
if [ -f "$SKILL_DIR/dev-shared-CLAUDE.md" ]; then
    install -o root -g root -m 644 "$SKILL_DIR/dev-shared-CLAUDE.md" "$SHARED_DIR/CLAUDE.md"
fi

# Install codex.md (always overwrite from chief copy if present)
if [ -f "$SKILL_DIR/codex.md" ]; then
    install -o root -g root -m 644 "$SKILL_DIR/codex.md" "$SHARED_DIR/codex.md"
fi

# Install DEV_GUIDE.md
if [ -f "$SKILL_DIR/DEV_GUIDE.md" ]; then
    install -o root -g root -m 644 "$SKILL_DIR/DEV_GUIDE.md" "$SHARED_DIR/DEV_GUIDE.md"
fi

# Install curated memory seed (always overwrite — chief manages content)
if [ -d "$SKILL_DIR/memory" ]; then
    rm -rf "$SHARED_DIR/memory"
    cp -r "$SKILL_DIR/memory" "$SHARED_DIR/memory"
fi

# Settings.json and hooks: intentionally NOT created/symlinked for devs.
# Devs use Claude's built-in defaults.

chown -R root:root "$SHARED_DIR"
find "$SHARED_DIR" -type d -exec chmod 755 {} +
find "$SHARED_DIR" -type f -exec chmod 644 {} +

# ============================================================================
# 4. setuid-wrapper /usr/local/bin/claude
# ============================================================================

if [ ! -x "$WRAPPER_PATH" ] || [ "$SKILL_DIR/setuid-claude-wrapper.c" -nt "$WRAPPER_PATH" ]; then
    log "compiling and installing setuid wrapper to $WRAPPER_PATH"
    if ! command -v gcc >/dev/null 2>&1; then
        err "gcc not installed — run 'apt install -y build-essential' and rerun"
        exit 1
    fi
    gcc -O2 -Wall -Wextra -o /tmp/claude-wrapper "$SKILL_DIR/setuid-claude-wrapper.c"
    install -o claude-runner -g claude-runner -m 4755 /tmp/claude-wrapper "$WRAPPER_PATH"
    rm -f /tmp/claude-wrapper
else
    log "setuid wrapper already at $WRAPPER_PATH"
fi

# ============================================================================
# 5. Bare repo /srv/git/VDole.git + hooks
# ============================================================================

if [ ! -d "$BARE_REPO" ]; then
    log "creating bare repo $BARE_REPO"
    mkdir -p "$(dirname "$BARE_REPO")"
    git init --bare --shared=group --initial-branch=main "$BARE_REPO"
    chgrp -R developers "$BARE_REPO"
    chmod -R g+ws "$BARE_REPO"
else
    log "bare repo $BARE_REPO already exists"
    # Ensure HEAD points to main (idempotent — fix if bare was init'd with default master)
    git -C "$BARE_REPO" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
fi

# Pre-set GitHub origin remote in bare (mirror-push runs as git-mirror — no write
# access to bare config). Idempotent.
GITHUB_REMOTE='git@github.com:ssv555/vdole.git'
if ! git -C "$BARE_REPO" remote get-url origin >/dev/null 2>&1; then
    git -C "$BARE_REPO" remote add origin "$GITHUB_REMOTE"
else
    git -C "$BARE_REPO" remote set-url origin "$GITHUB_REMOTE"
fi
# Bare doesn't track remotes — remove fetch refspec entirely to prevent
# "cannot lock ref refs/remotes/origin/*" warnings on every push (git tries to
# update remote-tracking refs after push, but bare has no refs/remotes/ dir
# AND git-mirror has no write perms on refs/heads either).
git -C "$BARE_REPO" config --unset-all remote.origin.fetch 2>/dev/null || true

# Always refresh hooks (idempotent — overwrites)
log "installing git hooks"
install -m 755 "$SKILL_DIR/pre-receive.sh"  "$BARE_REPO/hooks/pre-receive"
install -m 755 "$SKILL_DIR/post-receive.sh" "$BARE_REPO/hooks/post-receive"

# Lock down chief-controlled bare files so devs (in developers group) cannot
# tamper. Devs need write on objects/, refs/, packed-refs for push — leave those.
# But hooks/, config, HEAD, description are admin-only.
chmod g-w "$BARE_REPO/hooks"
chmod g-w "$BARE_REPO/config" "$BARE_REPO/HEAD" "$BARE_REPO/description" 2>/dev/null || true

# ============================================================================
# 6. Mirror queue + daemon
# ============================================================================

log "ensuring mirror queue $MIRROR_QUEUE_DIR/"
mkdir -p "$MIRROR_QUEUE_DIR"
chown root:git-mirror "$MIRROR_QUEUE_DIR"
chmod 0770 "$MIRROR_QUEUE_DIR"
touch "$MIRROR_QUEUE_DIR/queue"
chown root:git-mirror "$MIRROR_QUEUE_DIR/queue"
chmod 0660 "$MIRROR_QUEUE_DIR/queue"

log "installing mirror-push.sh"
mkdir -p "$MIRROR_HOME/bin" "$MIRROR_HOME/.ssh"

# Pre-create log file (systemd ReadWritePaths requires it to exist)
if [ ! -f /var/log/vdole-mirror.log ]; then
    touch /var/log/vdole-mirror.log
    chown git-mirror:git-mirror /var/log/vdole-mirror.log
    chmod 644 /var/log/vdole-mirror.log
fi

# Pre-create git-mirror's gitconfig with safe.directory (ProtectHome=read-only
# in systemd unit blocks runtime git config --global, so write it here)
GITCONFIG="$MIRROR_HOME/.gitconfig"
if ! grep -q "$BARE_REPO" "$GITCONFIG" 2>/dev/null; then
    cat > "$GITCONFIG" <<EOF
[safe]
    directory = $BARE_REPO
EOF
    chown git-mirror:git-mirror "$GITCONFIG"
    chmod 644 "$GITCONFIG"
fi
install -o root -g root -m 755 "$SKILL_DIR/mirror-push.sh" "$MIRROR_HOME/bin/mirror-push.sh"
chown git-mirror:git-mirror "$MIRROR_HOME/.ssh"
chmod 700 "$MIRROR_HOME/.ssh"

# Pre-populate known_hosts with github.com fingerprint
if [ ! -s "$MIRROR_HOME/.ssh/known_hosts" ]; then
    log "fetching github.com SSH fingerprint into $MIRROR_HOME/.ssh/known_hosts"
    ssh-keyscan -t ed25519,ecdsa,rsa github.com > "$MIRROR_HOME/.ssh/known_hosts" 2>/dev/null
    chown git-mirror:git-mirror "$MIRROR_HOME/.ssh/known_hosts"
    chmod 644 "$MIRROR_HOME/.ssh/known_hosts"
fi

# Bot SSH key — if absent, prompt to generate / accept
if [ ! -f "$MIRROR_HOME/.ssh/id_ed25519" ]; then
    warn "bot SSH key missing at $MIRROR_HOME/.ssh/id_ed25519"
    warn "generate now? (y/N)"
    read -r answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        sudo -u git-mirror ssh-keygen -t ed25519 -f "$MIRROR_HOME/.ssh/id_ed25519" -N '' -C 'vdole-git-mirror-bot'
        log "public key for bot account (add to bot's GitHub SSH settings):"
        cat "$MIRROR_HOME/.ssh/id_ed25519.pub"
    else
        warn "skipped — place bot key at $MIRROR_HOME/.ssh/id_ed25519 manually before mirror will work"
    fi
fi

# systemd unit + path watcher
log "installing systemd units"
install -o root -g root -m 644 "$SKILL_DIR/vdole-mirror.service" /etc/systemd/system/vdole-mirror.service
install -o root -g root -m 644 "$SKILL_DIR/vdole-mirror.path"    /etc/systemd/system/vdole-mirror.path

# Daily 06:00 cleanup of dev services on 40001-49999
log "installing dev-services-cleanup units (06:00 daily)"
# .sh already at $SKILL_DIR via Sync-LibToServer — only ensure perms
chown root:root "$SKILL_DIR/dev-services-cleanup.sh"
chmod 755       "$SKILL_DIR/dev-services-cleanup.sh"
install -o root -g root -m 644 "$SKILL_DIR/dev-services-cleanup.service" /etc/systemd/system/dev-services-cleanup.service
install -o root -g root -m 644 "$SKILL_DIR/dev-services-cleanup.timer"   /etc/systemd/system/dev-services-cleanup.timer

# Nightly 04:00 VACUUM ANALYZE on per-dev test DBs (vdole_*_test)
log "installing dev-test-db-vacuum units (04:00 nightly)"
chown root:root "$SKILL_DIR/dev-test-db-vacuum.sh"
chmod 755       "$SKILL_DIR/dev-test-db-vacuum.sh"
install -o root -g root -m 644 "$SKILL_DIR/dev-test-db-vacuum.service" /etc/systemd/system/dev-test-db-vacuum.service
install -o root -g root -m 644 "$SKILL_DIR/dev-test-db-vacuum.timer"   /etc/systemd/system/dev-test-db-vacuum.timer

# Pre-create log files (systemd ReadWritePaths)
if [ ! -f /var/log/dev-services-cleanup.log ]; then
    touch /var/log/dev-services-cleanup.log
    chmod 644 /var/log/dev-services-cleanup.log
fi
if [ ! -f /var/log/dev-test-db-vacuum.log ]; then
    touch /var/log/dev-test-db-vacuum.log
    chmod 644 /var/log/dev-test-db-vacuum.log
fi

systemctl daemon-reload
systemctl enable --now vdole-mirror.path
systemctl enable --now dev-services-cleanup.timer
systemctl enable --now dev-test-db-vacuum.timer
log "systemctl status vdole-mirror.path:"
systemctl status --no-pager vdole-mirror.path || true
log "systemctl status dev-services-cleanup.timer:"
systemctl status --no-pager dev-services-cleanup.timer || true
log "systemctl status dev-test-db-vacuum.timer:"
systemctl status --no-pager dev-test-db-vacuum.timer || true

# ============================================================================
# 7. sudoers — %developers may invoke mirror-push.sh as git-mirror (NOPASSWD)
# ============================================================================

SUDOERS_FILE='/etc/sudoers.d/vdole-mirror'
if [ ! -f "$SUDOERS_FILE" ]; then
    log "installing sudoers rule $SUDOERS_FILE"
    cat > "$SUDOERS_FILE" <<'EOF'
# Allow developers to trigger mirror-push as git-mirror without password.
%developers ALL=(git-mirror) NOPASSWD: /home/git-mirror/bin/mirror-push.sh *
EOF
    chmod 0440 "$SUDOERS_FILE"
    visudo -cf "$SUDOERS_FILE" || { err "sudoers syntax error in $SUDOERS_FILE"; rm -f "$SUDOERS_FILE"; exit 1; }
else
    log "sudoers rule $SUDOERS_FILE already exists"
fi

# ============================================================================
# 8. Marker
# ============================================================================

touch "$SKILL_DIR/.bootstrap-ok"
log "bootstrap complete"
