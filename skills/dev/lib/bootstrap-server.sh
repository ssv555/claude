#!/usr/bin/env bash
# bootstrap-server.sh — idempotent server bootstrap for /dev skill.
#
# Creates system users, shared claude env, plain claude symlink, bare VDole repo,
# git-mirror daemon, Anthropic IPv4 hosts (forces traffic via wg0 → Amsterdam),
# ACL exceptions for webdev creds access.
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
WEBDEV_HOME='/var/lib/webdev'
WEBDEV_UID=1600

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

ensure_group() {
    local name="$1"
    if getent group "$name" >/dev/null 2>&1; then
        log "group '$name' exists"
        return 0
    fi
    log "creating group '$name'"
    groupadd "$name"
}

# webdev — auth-holder for shared Claude OAuth. Needs real shell (/bin/bash) because
# Anthropic refuses login from accounts with nologin shell. Specific UID 1600
# (regular range >=1000) — Anthropic also rejects 'system' UIDs (<1000).
# /var/lib/webdev/.claude/.credentials.json is the master OAuth token; per-dev
# add-user.sh COPIES it into /home/<dev>/.claude/.credentials.json.
if ! id -u webdev >/dev/null 2>&1; then
    log "creating webdev (UID $WEBDEV_UID, shell /bin/bash, HOME $WEBDEV_HOME)"
    useradd --uid $WEBDEV_UID --create-home --home-dir "$WEBDEV_HOME" --shell /bin/bash webdev
    # TERM/LC_ALL for chief running OAuth via `sudo -u webdev -i`
    cat >> "$WEBDEV_HOME/.bashrc" <<'BASHRC_EOF'

# Force modern TERM for claude TUI rendering (Termius default vt100 breaks it)
export TERM=xterm-256color
export LC_ALL=en_US.UTF-8
BASHRC_EOF
    chown webdev:webdev "$WEBDEV_HOME/.bashrc"
else
    log "user 'webdev' exists"
fi

# git-mirror — internal bot pushing bare → GitHub
if ! id -u git-mirror >/dev/null 2>&1; then
    log "creating git-mirror (system, nologin)"
    useradd --system --create-home --home-dir "$MIRROR_HOME" --shell /usr/sbin/nologin git-mirror
else
    log "user 'git-mirror' exists"
fi

ensure_group 'developers'

# ============================================================================
# 1a. Filesystem isolation via ACL — devs (group 'developers') blocked from
#     sensitive paths; narrow exceptions punched for webdev creds access.
# ============================================================================
if ! command -v setfacl >/dev/null 2>&1; then
    log "installing acl package"
    DEBIAN_FRONTEND=noninteractive apt-get install -y acl >/dev/null 2>&1 || warn "apt install acl failed"
fi

if command -v setfacl >/dev/null 2>&1; then
    if [ -d /var/www ] && [ "$(stat -c '%a' /var/www)" = "777" ]; then
        log "fixing /var/www 777 -> 755"
        chmod 755 /var/www
    fi

    # Full block: dev cannot enter or list
    for p in /var /backup /lost+found /snap /media /mnt /cdrom \
             /opt/certbot /opt/containerd /opt/dev-skill /opt/qdrant; do
        [ -e "$p" ] && setfacl -m g:developers:--- "$p" 2>/dev/null || true
    done

    # Traverse-only: dev cd's to known subpath but cannot ls parent
    for p in /home /opt /srv /srv/git; do
        [ -e "$p" ] && setfacl -m g:developers:--x "$p" 2>/dev/null || true
    done

    # === Narrow exception: traverse /var/lib/* down to webdev's creds ===
    # Devs need read access to /var/lib/webdev/.claude/.credentials.json (master OAuth)
    # to bootstrap their own copy. Other /var paths remain fully blocked.
    setfacl -m g:developers:--x /var          2>/dev/null || true
    setfacl -m g:developers:--x /var/lib      2>/dev/null || true
    setfacl -m g:developers:--x "$WEBDEV_HOME" 2>/dev/null || true
    setfacl -m g:developers:r-x "$WEBDEV_HOME/.claude" 2>/dev/null || true

    log "filesystem isolation ACLs applied + webdev creds exception"
fi

# ============================================================================
# 1b. sshd AllowGroups — ensure 'developers' allowed
# ============================================================================
HARDENING='/etc/ssh/sshd_config.d/01-hardening.conf'
if [ -f "$HARDENING" ]; then
    if grep -qE '^AllowGroups' "$HARDENING"; then
        if ! grep -qE '^AllowGroups[[:space:]].*\bdevelopers\b' "$HARDENING"; then
            log "appending 'developers' to AllowGroups in $HARDENING"
            sed -i 's|^\(AllowGroups[[:space:]].*\)$|\1 developers|' "$HARDENING"
            sshd -t && systemctl reload ssh && log "sshd reloaded"
        fi
    else
        warn "sshd hardening file has no AllowGroups — devs may be blocked. Check $HARDENING."
    fi
fi

# ============================================================================
# 1c. Block SFTP for developers + audit-log SFTP
# ============================================================================
SFTP_BLOCK='/etc/ssh/sshd_config.d/02-developers-no-sftp.conf'
if [ ! -f "$SFTP_BLOCK" ]; then
    log "installing SFTP block + audit for developers"
    cat > "$SFTP_BLOCK" <<'EOF'
# Block SFTP/WinSCP/scp for developers — interactive shell (claude, mc) still works.
# NOT using ForceCommand (it breaks PTY allocation → black screen in TUI apps).
Match Group developers
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    AllowAgentForwarding no
    Subsystem sftp /bin/false
EOF
    chmod 644 "$SFTP_BLOCK"
fi

SFTP_AUDIT='/etc/ssh/sshd_config.d/03-sftp-audit.conf'
if [ ! -f "$SFTP_AUDIT" ]; then
    log "installing SFTP audit-log"
    cat > "$SFTP_AUDIT" <<'EOF'
# Audit-log SFTP for non-developers (chief/admin). Logged to journalctl -u ssh.
Subsystem sftp /usr/lib/openssh/sftp-server -l INFO -f AUTH
EOF
    chmod 644 "$SFTP_AUDIT"
fi

sshd -t && systemctl reload ssh && log "sshd reloaded (SFTP block + audit)"

# ============================================================================
# 1d. /etc/hosts — force IPv4 for Anthropic domains
# ============================================================================
# wg0 tunnel routes IPv4 ranges to Amsterdam exit. IPv6 (AAAA) goes via ens3 (moscow)
# → Anthropic geo-blocks moscow IPs with 403. Pinning IPv4 IPs in /etc/hosts
# guarantees all claude traffic goes through Amsterdam regardless of DNS state.
# Update IPs periodically (Cloudflare may rotate; check with `dig +short A api.anthropic.com @1.1.1.1`).
if ! grep -q '# === Anthropic IPv4 forcing' /etc/hosts; then
    log "adding Anthropic IPv4 mappings to /etc/hosts"
    cat >> /etc/hosts <<'EOF'

# === Anthropic IPv4 forcing — wg0 tunnel only routes IPv4 to Amsterdam ===
160.79.104.10 api.anthropic.com
160.79.104.10 api-staging.anthropic.com
160.79.104.10 mcp-proxy.anthropic.com
160.79.104.10 docs.anthropic.com
160.79.104.10 support.anthropic.com
160.79.104.10 www.anthropic.com
160.79.104.10 console.anthropic.com
160.79.104.10 code.claude.com
160.79.104.10 platform.claude.com
160.79.104.10 docs.claude.com
160.79.104.10 support.claude.com
160.79.104.10 claude.com
160.79.104.10 claude.ai
160.79.104.10 statsig.anthropic.com
# === END Anthropic ===
EOF
fi

# ============================================================================
# 1d-bis. Custom motd for developers — replaces stock Ubuntu banner.
# Devs get ~/.hushlogin in add-user.sh to suppress stock motd; we install
# /etc/update-motd.d/99-dev-welcome as a soft custom replacement that shows:
# alias, repo+branch, rules-acceptance status, restart-required warning,
# skill shortcuts. Failure to render NEVER blocks login (script exits 0).
# ============================================================================
MOTD_SRC="$SKILL_DIR/99-dev-welcome"
MOTD_DST='/etc/update-motd.d/99-dev-welcome'
if [ -f "$MOTD_SRC" ]; then
    log "installing custom dev-welcome motd → $MOTD_DST"
    install -o root -g root -m 755 "$MOTD_SRC" "$MOTD_DST"
else
    warn "motd source missing at $MOTD_SRC — skipping custom welcome"
fi

# ============================================================================
# 1e. bun + bunx in /usr/local/bin/ — readable by all
# ============================================================================
fix_bun_link() {
    local name="$1"
    local p="/usr/local/bin/$name"
    if [ ! -e "$p" ]; then
        warn "$p missing — install bun manually, then rerun bootstrap"
        return
    fi
    if [ -L "$p" ]; then
        local target
        target=$(readlink -f "$p")
        if [ -z "$target" ] || [ ! -r "$target" ]; then
            warn "$p is a dead symlink (target=$target) — install bun globally"
            return
        fi
        case "$target" in
            /home/*)
                log "$p is symlink into chief-home ($target) — replacing with real binary"
                rm "$p"
                cp "$target" "$p"
                chown root:root "$p"
                chmod 755 "$p"
                ;;
        esac
    fi
}

fix_bun_link bun
fix_bun_link bunx

# ============================================================================
# 2. claude CLI — install into /opt/claude/
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
                err "neither bun nor npm available"
                exit 1
            fi
        }
    elif command -v npm >/dev/null 2>&1; then
        npm install --prefix "$CLAUDE_BIN_DIR" -g @anthropic-ai/claude-code
    else
        err "neither bun nor npm available"
        exit 1
    fi
    chown -R root:root "$CLAUDE_BIN_DIR"
else
    log "claude CLI already at $CLAUDE_BIN_DIR/"
fi

# ============================================================================
# 3. /opt/claude-shared/ — shared read-only config (skills, CLAUDE.md, codex.md, DEV_GUIDE.md, memory/)
# ============================================================================
log "ensuring $SHARED_DIR/ skeleton"
mkdir -p "$SHARED_DIR/skills" "$SHARED_DIR/memory"

[ -f "$SKILL_DIR/dev-shared-CLAUDE.md" ] && install -o root -g root -m 644 "$SKILL_DIR/dev-shared-CLAUDE.md" "$SHARED_DIR/CLAUDE.md"
[ -f "$SKILL_DIR/codex.md" ]     && install -o root -g root -m 644 "$SKILL_DIR/codex.md"     "$SHARED_DIR/codex.md"
[ -f "$SKILL_DIR/DEV_GUIDE.md" ] && install -o root -g root -m 644 "$SKILL_DIR/DEV_GUIDE.md" "$SHARED_DIR/DEV_GUIDE.md"
# Managed Claude Code settings: headless server has no browser/desktop → kill
# playwright/desktop MCP, block project .mcp.json auto-enable, mute telemetry/updater.
[ -f "$SKILL_DIR/dev-shared-settings.json" ] && install -o root -g root -m 644 "$SKILL_DIR/dev-shared-settings.json" "$SHARED_DIR/settings.json"

if [ -d "$SKILL_DIR/memory" ]; then
    rm -rf "$SHARED_DIR/memory"
    cp -r "$SKILL_DIR/memory" "$SHARED_DIR/memory"
fi

chown -R root:root "$SHARED_DIR"
find "$SHARED_DIR" -type d -exec chmod 755 {} +
find "$SHARED_DIR" -type f -exec chmod 644 {} +

# ============================================================================
# 4. /usr/local/bin/claude — plain symlink (NO setuid wrapper)
# ============================================================================
# Previously this was a setuid C-wrapper switching to claude-runner. Anthropic
# rejects that flow: getpwuid(real_uid).pw_dir vs HOME mismatch → "account not
# available". Solution: claude runs AS THE DEV (UID 1002 = spc), credentials are
# copied from webdev's master into per-dev HOME. Wrapper is removed.
if [ -L "$WRAPPER_PATH" ] && [ "$(readlink "$WRAPPER_PATH")" = "$CLAUDE_BIN_DIR/bin/claude" ]; then
    log "claude symlink already at $WRAPPER_PATH"
else
    log "installing $WRAPPER_PATH as plain symlink to $CLAUDE_BIN_DIR/bin/claude"
    rm -f "$WRAPPER_PATH"
    ln -s "$CLAUDE_BIN_DIR/bin/claude" "$WRAPPER_PATH"
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
    git -C "$BARE_REPO" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
fi

GITHUB_REMOTE='git@github.com:ssv555/vdole.git'
if ! git -C "$BARE_REPO" remote get-url origin >/dev/null 2>&1; then
    git -C "$BARE_REPO" remote add origin "$GITHUB_REMOTE"
else
    git -C "$BARE_REPO" remote set-url origin "$GITHUB_REMOTE"
fi
git -C "$BARE_REPO" config --unset-all remote.origin.fetch 2>/dev/null || true

log "installing git hooks"
install -m 755 "$SKILL_DIR/pre-receive.sh"  "$BARE_REPO/hooks/pre-receive"
install -m 755 "$SKILL_DIR/post-receive.sh" "$BARE_REPO/hooks/post-receive"

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

if [ ! -f /var/log/vdole-mirror.log ]; then
    touch /var/log/vdole-mirror.log
    chown git-mirror:git-mirror /var/log/vdole-mirror.log
    chmod 644 /var/log/vdole-mirror.log
fi

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

if [ ! -s "$MIRROR_HOME/.ssh/known_hosts" ]; then
    log "fetching github.com SSH fingerprint"
    ssh-keyscan -t ed25519,ecdsa,rsa github.com > "$MIRROR_HOME/.ssh/known_hosts" 2>/dev/null
    chown git-mirror:git-mirror "$MIRROR_HOME/.ssh/known_hosts"
    chmod 644 "$MIRROR_HOME/.ssh/known_hosts"
fi

if [ ! -f "$MIRROR_HOME/.ssh/id_ed25519" ]; then
    warn "bot SSH key missing at $MIRROR_HOME/.ssh/id_ed25519 — place manually before mirror works"
fi

log "installing systemd units"
install -o root -g root -m 644 "$SKILL_DIR/vdole-mirror.service" /etc/systemd/system/vdole-mirror.service
install -o root -g root -m 644 "$SKILL_DIR/vdole-mirror.path"    /etc/systemd/system/vdole-mirror.path

log "installing dev-services-cleanup units (06:00 daily)"
chown root:root "$SKILL_DIR/dev-services-cleanup.sh"
chmod 755       "$SKILL_DIR/dev-services-cleanup.sh"
install -o root -g root -m 644 "$SKILL_DIR/dev-services-cleanup.service" /etc/systemd/system/dev-services-cleanup.service
install -o root -g root -m 644 "$SKILL_DIR/dev-services-cleanup.timer"   /etc/systemd/system/dev-services-cleanup.timer

log "installing dev-test-db-vacuum units (04:00 nightly)"
chown root:root "$SKILL_DIR/dev-test-db-vacuum.sh"
chmod 755       "$SKILL_DIR/dev-test-db-vacuum.sh"
install -o root -g root -m 644 "$SKILL_DIR/dev-test-db-vacuum.service" /etc/systemd/system/dev-test-db-vacuum.service
install -o root -g root -m 644 "$SKILL_DIR/dev-test-db-vacuum.timer"   /etc/systemd/system/dev-test-db-vacuum.timer

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
    visudo -cf "$SUDOERS_FILE" || { err "sudoers syntax error"; rm -f "$SUDOERS_FILE"; exit 1; }
else
    log "sudoers rule already exists"
fi

# ============================================================================
# 7a. RULES gate — RULES.md + helper + sudoers + profile.d + audit dirs.
# Devs must accept RULES.md (SHA-256 versioned) on every interactive shell
# login before they get a prompt. Acceptance flag root-owned (devs cannot
# forge). Updated rules → re-acceptance required (hash changes).
# ============================================================================

# /opt/claude-shared/RULES.md — install from template, set the hash file
RULES_SRC="$SKILL_DIR/RULES.template.md"
RULES_DST="$SHARED_DIR/RULES.md"
if [ -f "$RULES_SRC" ]; then
    log "installing RULES.md → $RULES_DST"
    install -o root -g root -m 644 "$RULES_SRC" "$RULES_DST"
    # Hash file is world-readable (used by motd to verify acceptance status)
    sha256sum "$RULES_DST" | awk '{print $1}' > "$SHARED_DIR/RULES.version"
    chown root:root "$SHARED_DIR/RULES.version"
    chmod 644 "$SHARED_DIR/RULES.version"
else
    warn "RULES.template.md missing — rules gate will fail-open"
fi

# Acceptance flag directory (root-owned, world-traversable; flags world-readable)
mkdir -p "$SHARED_DIR/rules_acceptances"
chown root:root "$SHARED_DIR/rules_acceptances"
chmod 755 "$SHARED_DIR/rules_acceptances"

# Audit directory (root-only readable — devs MUST NOT see who/when accepted what)
mkdir -p "$SHARED_DIR/audit"
chown root:root "$SHARED_DIR/audit"
chmod 750 "$SHARED_DIR/audit"

# /usr/local/sbin/dev-accept-rules — privileged helper (writes flag, audit-log)
HELPER_SRC="$SKILL_DIR/dev-accept-rules.sh"
HELPER_DST='/usr/local/sbin/dev-accept-rules'
if [ -f "$HELPER_SRC" ]; then
    log "installing $HELPER_DST"
    install -o root -g root -m 750 "$HELPER_SRC" "$HELPER_DST"
else
    warn "dev-accept-rules.sh missing — rules gate disabled"
fi

# sudoers — %developers can call the helper NOPASSWD with exactly one arg shape
SUDOERS_RULES='/etc/sudoers.d/dev-accept-rules'
if [ ! -f "$SUDOERS_RULES" ]; then
    log "installing sudoers rule $SUDOERS_RULES"
    cat > "$SUDOERS_RULES" <<'EOF'
# Allow developers to record their RULES.md acceptance via the privileged helper.
# Restricted to the exact verb 'accept' followed by a single positional arg
# (the rules hash). Helper re-derives identity from SUDO_USER and re-hashes the
# rules file itself — the supplied hash is only echoed back for the audit log.
%developers ALL=(root) NOPASSWD: /usr/local/sbin/dev-accept-rules accept *
EOF
    chmod 0440 "$SUDOERS_RULES"
    visudo -cf "$SUDOERS_RULES" || { err "sudoers syntax error in $SUDOERS_RULES"; rm -f "$SUDOERS_RULES"; exit 1; }
else
    log "sudoers rule $SUDOERS_RULES already exists"
fi

# /etc/profile.d/00-rules-check.sh — the gate itself
GATE_SRC="$SKILL_DIR/00-rules-check.sh"
GATE_DST='/etc/profile.d/00-rules-check.sh'
if [ -f "$GATE_SRC" ]; then
    log "installing rules gate → $GATE_DST"
    install -o root -g root -m 755 "$GATE_SRC" "$GATE_DST"
else
    warn "rules gate source missing — devs will not see acceptance prompt"
fi

# ============================================================================
# 7b. dev-NN-* skill audit-log helper + chief notifier
# ============================================================================

# Append-only audit logger called by every /dev-NN-* skill
AUDIT_SRC="$SKILL_DIR/dev-audit-log.sh"
AUDIT_DST='/usr/local/sbin/dev-audit-log'
if [ -f "$AUDIT_SRC" ]; then
    log "installing $AUDIT_DST"
    install -o root -g root -m 750 "$AUDIT_SRC" "$AUDIT_DST"
fi

# /dev-09-finish notifier (audit + optional HTTP webhook to chief's TG bridge)
NOTIFY_SRC="$SKILL_DIR/dev-notify-finish.sh"
NOTIFY_DST='/usr/local/sbin/dev-notify-finish'
if [ -f "$NOTIFY_SRC" ]; then
    log "installing $NOTIFY_DST"
    install -o root -g root -m 750 "$NOTIFY_SRC" "$NOTIFY_DST"
fi

# sudoers — %developers may invoke audit-log + finish notifier NOPASSWD.
# Helpers self-validate inputs; sudoers is just the auth grant.
SUDOERS_DEV_SKILLS='/etc/sudoers.d/dev-skills-helpers'
if [ ! -f "$SUDOERS_DEV_SKILLS" ]; then
    log "installing sudoers rule $SUDOERS_DEV_SKILLS"
    cat > "$SUDOERS_DEV_SKILLS" <<'EOF'
# Allow developers to write to root-owned audit logs via dedicated helpers.
# Helpers validate inputs and use SUDO_USER for identity.
%developers ALL=(root) NOPASSWD: /usr/local/sbin/dev-audit-log
%developers ALL=(root) NOPASSWD: /usr/local/sbin/dev-notify-finish
EOF
    chmod 0440 "$SUDOERS_DEV_SKILLS"
    visudo -cf "$SUDOERS_DEV_SKILLS" || { err "sudoers syntax error in $SUDOERS_DEV_SKILLS"; rm -f "$SUDOERS_DEV_SKILLS"; exit 1; }
else
    log "sudoers rule $SUDOERS_DEV_SKILLS already exists"
fi

# ============================================================================
# 8. Marker + post-bootstrap manual step reminder
# ============================================================================
touch "$SKILL_DIR/.bootstrap-ok"
log "bootstrap complete"

if [ ! -s "$WEBDEV_HOME/.claude/.credentials.json" ] 2>/dev/null; then
    cat <<EOF

================================================================================
NEXT STEP (manual, one-time): authenticate webdev's Claude account.

    sudo -u webdev -i
    claude

In TUI: select '1. Claude account with subscription' → open URL in your local
browser → log into Pro/Max → paste code back. Exit when 'Claude Code' welcome
shows. The token gets saved to:

    $WEBDEV_HOME/.claude/.credentials.json

After that, /dev add <alias> automatically copies it into each dev's HOME.
================================================================================
EOF
fi
