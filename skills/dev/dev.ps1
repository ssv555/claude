# dev.ps1 — main dispatcher for /dev skill
# Chief-only. Runs on Windows PC (PC-SKY). SSH's to moscow_my for server-side ops.
#
# Usage:
#   dev.ps1                                 # list
#   dev.ps1 list
#   dev.ps1 show <alias>
#   dev.ps1 add
#   dev.ps1 del <alias>
#   dev.ps1 sync-skills [<alias>|all]
#   dev.ps1 bootstrap

[CmdletBinding()]
param(
    [string]$Subcommand = 'list',
    [string]$Arg1 = '',
    [string]$Arg2 = ''
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Constants
# ============================================================================

$SSH_HOST           = 'moscow_my'
$SERVER_SKILL_DIR   = '/opt/dev-skill'
$DEVELOPERS_DIR     = Join-Path $env:USERPROFILE '.claude\developers'
$ALLOWLIST_PATH     = Join-Path $DEVELOPERS_DIR 'skills_allowlist.json'
$KEYS_CLIENT_ROOT   = 'D:\Data\Backup\Ubuntu-Servers\moscow_my\keys-client'
$SSH_INVENTORY_PATH = 'D:\Data\Backup\Ubuntu-Servers\moscow_my\SSH_KEYS_INVENTORY.md'
$DIALOG_PS1         = Join-Path $env:USERPROFILE '.claude\scripts\dialog.ps1'

$LIB_DIR = Join-Path $PSScriptRoot 'lib'

# ============================================================================
# Helpers
# ============================================================================

function Assert-Chief {
    $whoami = $env:USERNAME
    $host_  = $env:COMPUTERNAME
    if (-not ($whoami -eq 'ssv555' -or $host_ -eq 'PC-SKY')) {
        Write-Host "Forbidden: /dev is chief-only (current: $whoami@$host_)" -ForegroundColor Red
        exit 1
    }
}

function Sync-LibToServer {
    # Copy lib/*.sh + .c + systemd units to /opt/dev-skill/ on the server.
    Write-Host "[sync] uploading lib/ to ${SSH_HOST}:${SERVER_SKILL_DIR}/ ..." -ForegroundColor DarkGray
    & ssh $SSH_HOST "sudo mkdir -p $SERVER_SKILL_DIR && sudo chown `$(id -u):`$(id -g) $SERVER_SKILL_DIR"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create $SERVER_SKILL_DIR on server" }

    & scp -qr "$LIB_DIR/." "${SSH_HOST}:${SERVER_SKILL_DIR}/"
    if ($LASTEXITCODE -ne 0) { throw "scp of lib/ failed" }

    & ssh $SSH_HOST "sudo chown -R root:root $SERVER_SKILL_DIR && sudo chmod 755 $SERVER_SKILL_DIR/*.sh"
    if ($LASTEXITCODE -ne 0) { throw "Failed to chown/chmod $SERVER_SKILL_DIR/" }
}

function Ensure-Bootstrap {
    # Check marker file; if absent, run bootstrap.
    & ssh $SSH_HOST "test -f $SERVER_SKILL_DIR/.bootstrap-ok" 2>$null
    if ($LASTEXITCODE -eq 0) { return }

    Write-Host "[bootstrap] server not bootstrapped yet — running bootstrap-server.sh" -ForegroundColor Yellow
    Sync-LibToServer
    & ssh $SSH_HOST "sudo bash $SERVER_SKILL_DIR/bootstrap-server.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "Bootstrap failed"
    }
    Write-Host "[bootstrap] OK" -ForegroundColor Green
}

function Read-Allowlist {
    if (-not (Test-Path $ALLOWLIST_PATH)) {
        throw "Allowlist not found: $ALLOWLIST_PATH"
    }
    return (Get-Content $ALLOWLIST_PATH -Raw | ConvertFrom-Json)
}

function Ask {
    # Wrapper around dialog.ps1 (works in both main session and subagents).
    param([string]$Question, [string]$Default = '')
    if (Test-Path $DIALOG_PS1) {
        $result = & $DIALOG_PS1 -Question $Question -Default $Default
        return $result
    } else {
        # Fallback: stdin
        $defaultLabel = if ($Default) { " [$Default]" } else { '' }
        $r = Read-Host "$Question$defaultLabel"
        if (-not $r) { $r = $Default }
        return $r
    }
}

function Format-Bytes {
    param([long]$Bytes)
    $units = 'B', 'K', 'M', 'G', 'T'
    $i = 0
    $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt 4) { $v /= 1024; $i++ }
    return ('{0:N1}{1}' -f $v, $units[$i])
}

function Get-NextPortBlock {
    # Scan moscow_my nginx confs for occupied port bases (40001, 40011, ...) and
    # return the next free 10-port block in range 40000..49991.
    $occupied = & ssh $SSH_HOST "grep -hoE 'proxy_pass http://127\\.0\\.0\\.1:[0-9]+' /etc/nginx/conf.d/dev-*.it-joy.ru.conf 2>/dev/null | grep -oE '[0-9]+$' | sort -un"
    $used = @{}
    foreach ($p in $occupied -split "`n") {
        if ($p -match '^\d+$') { $used[[int]$p] = $true }
    }
    for ($base = 40001; $base -le 49991; $base += 10) {
        $collide = $false
        # block uses base, base+1, base+2, base+4
        foreach ($off in 0, 1, 2, 4) {
            if ($used.ContainsKey($base + $off)) { $collide = $true; break }
        }
        if (-not $collide) { return $base }
    }
    throw "no free port block in 40000-49999 (max 100 devs reached?)"
}

function New-NginxConfForDev {
    # Generates /etc/nginx/conf.d/dev-<alias>.it-joy.ru.conf from lib/nginx-dev-template.conf
    # Issues Let's Encrypt cert via certbot --webroot. Reloads nginx.
    param([string]$Alias, [int]$PortBase)
    $api = $PortBase
    $hmr = $PortBase + 1
    $remoteConf = "/etc/nginx/conf.d/dev-$Alias.it-joy.ru.conf"
    $remoteWebroot = "/var/www/dev-$Alias.it-joy.ru"

    Write-Host "[nginx] provisioning dev-$Alias.it-joy.ru (API=$api HMR=$hmr)" -ForegroundColor DarkGray

    # 1. Stub HTTP-only conf for ACME challenge
    $stub = @"
server {
    listen 80;
    server_name dev-$Alias.it-joy.ru;
    root $remoteWebroot;
    location /.well-known/acme-challenge/ { root $remoteWebroot; }
    location / { return 404; }
}
"@
    $stubFile = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($stubFile, $stub, (New-Object Text.UTF8Encoding $false))

    & ssh $SSH_HOST "sudo mkdir -p $remoteWebroot && sudo chown root:nginx $remoteWebroot && sudo chmod 750 $remoteWebroot"
    & scp -q $stubFile "${SSH_HOST}:/tmp/dev-$Alias-stub.conf"
    Remove-Item $stubFile -Force
    & ssh $SSH_HOST "sudo cp /tmp/dev-$Alias-stub.conf $remoteConf && sudo rm /tmp/dev-$Alias-stub.conf && sudo nginx -t && sudo systemctl reload nginx"
    if ($LASTEXITCODE -ne 0) { throw "nginx stub install failed" }

    # 2. Copy error pages from existing dev.it-joy.ru webroot if available
    & ssh $SSH_HOST "test -f /var/www/dev.it-joy.ru/404.html && sudo cp -n /var/www/dev.it-joy.ru/404.html /var/www/dev.it-joy.ru/50x.html $remoteWebroot/ 2>/dev/null; true"

    # 3. Issue Let's Encrypt cert via webroot
    Write-Host "[certbot] issuing cert for dev-$Alias.it-joy.ru" -ForegroundColor DarkGray
    & ssh $SSH_HOST "sudo certbot certonly --webroot -w $remoteWebroot -d dev-$Alias.it-joy.ru --non-interactive --agree-tos -m ssv555ssv@gmail.com 2>&1 | tail -5"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[certbot] failed — keeping HTTP stub (DNS for dev-$Alias.it-joy.ru must point to moscow_my)" -ForegroundColor Yellow
        return
    }

    # 4. Render full HTTPS conf from template
    $templatePath = Join-Path $LIB_DIR 'nginx-dev-template.conf'
    if (-not (Test-Path $templatePath)) { throw "nginx template missing: $templatePath" }
    $tpl = Get-Content $templatePath -Raw
    $rendered = $tpl.Replace('{{ALIAS}}', $Alias).Replace('{{PORT_API}}', "$api").Replace('{{PORT_HMR}}', "$hmr")
    $renderedFile = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($renderedFile, $rendered, (New-Object Text.UTF8Encoding $false))
    & scp -q $renderedFile "${SSH_HOST}:/tmp/dev-$Alias.conf"
    Remove-Item $renderedFile -Force
    & ssh $SSH_HOST "sudo cp /tmp/dev-$Alias.conf $remoteConf && sudo rm /tmp/dev-$Alias.conf && sudo nginx -t && sudo systemctl reload nginx"
    if ($LASTEXITCODE -ne 0) { throw "nginx full conf install failed" }
    Write-Host "[nginx] dev-$Alias.it-joy.ru ready" -ForegroundColor Green
}

function Remove-NginxConfForDev {
    param([string]$Alias)
    $remoteConf = "/etc/nginx/conf.d/dev-$Alias.it-joy.ru.conf"
    & ssh $SSH_HOST "sudo rm -f $remoteConf && sudo certbot delete --cert-name dev-$Alias.it-joy.ru --non-interactive 2>/dev/null; sudo rm -rf /var/www/dev-$Alias.it-joy.ru; sudo nginx -t && sudo systemctl reload nginx"
}

# ============================================================================
# Subcommands
# ============================================================================

function Cmd-List {
    Sync-LibToServer
    $json = & ssh $SSH_HOST "sudo bash $SERVER_SKILL_DIR/list-users.sh"
    if ($LASTEXITCODE -ne 0) { throw "list-users.sh failed" }

    $devs = $json | ConvertFrom-Json
    if (-not $devs -or $devs.Count -eq 0) {
        Write-Host "No dev users on $SSH_HOST yet." -ForegroundColor DarkGray
        return
    }

    $sorted = $devs | Sort-Object @{Expression='last_activity'; Descending=$true}, @{Expression='alias'; Descending=$false}
    $rows = $sorted | ForEach-Object {
        [PSCustomObject]@{
            alias       = $_.alias
            created     = $_.created_at.Substring(0, 10)
            last        = if ($_.last_activity) { $_.last_activity.Substring(0, 10) } else { '-' }
            sessions    = $_.session_count
            home_size   = Format-Bytes ([long]$_.home_bytes)
        }
    }
    $rows | Format-Table -AutoSize
}

function Cmd-Show {
    param([string]$Alias)
    if (-not $Alias) { throw "Usage: dev.ps1 show <alias>" }
    Sync-LibToServer

    $json = & ssh $SSH_HOST "sudo bash $SERVER_SKILL_DIR/list-users.sh '$Alias'"
    if ($LASTEXITCODE -ne 0) { throw "list-users.sh failed for $Alias" }

    $dev = ($json | ConvertFrom-Json) | Where-Object alias -eq $Alias | Select-Object -First 1
    if (-not $dev) {
        Write-Host "No such dev: $Alias" -ForegroundColor Red
        exit 1
    }

    # Local meta
    $infoPath = Join-Path $DEVELOPERS_DIR "$Alias\info.json"
    $localInfo = if (Test-Path $infoPath) { Get-Content $infoPath -Raw | ConvertFrom-Json } else { $null }

    Write-Host ""
    Write-Host "alias        : $($dev.alias)"
    Write-Host "full name    : $(if ($localInfo) { $localInfo.full_name } else { '-' })"
    Write-Host "email        : $(if ($localInfo) { $localInfo.email } else { '-' })"
    Write-Host "created      : $($dev.created_at)"
    Write-Host "last activity: $($dev.last_activity)"
    Write-Host "sessions     : $($dev.session_count)"
    Write-Host "home size    : $(Format-Bytes ([long]$dev.home_bytes))"
    Write-Host "ssh key fp   : $(if ($localInfo) { $localInfo.ssh_key_fp } else { '-' })"
    Write-Host "status       : $(if ($localInfo) { $localInfo.status } else { 'active' })"
    Write-Host ""
}

function Cmd-Add {
    param(
        [string]$PreAlias = '',
        [string]$RepoName = ''
    )
    Sync-LibToServer
    Ensure-Bootstrap

    if ($PreAlias -and $PreAlias -match '^[a-z][a-z0-9_]{2,15}$') {
        $alias = $PreAlias
        Write-Host "[add] alias: $alias" -ForegroundColor DarkGray
    } else {
        $alias = Ask -Question 'Alias (Linux username, 3-16 lowercase letters)'
        if (-not $alias -or $alias -notmatch '^[a-z][a-z0-9_]{2,15}$') {
            throw "Invalid alias: '$alias'. Must match ^[a-z][a-z0-9_]{2,15}$"
        }
    }

    # Reject duplicates
    $existing = & ssh $SSH_HOST "id -u $alias 2>/dev/null"
    if ($LASTEXITCODE -eq 0) { throw "User $alias already exists on $SSH_HOST" }

    $fullName = Ask -Question 'Full name (RU or EN)'
    if (-not $fullName) { throw "Full name required" }

    # Auto-gen email: <alias>@moscow.my
    $email = "$alias@moscow.my"

    # Repo to clone
    if ($RepoName) {
        $repo = $RepoName.ToLower()
    } else {
        $repo = (Ask -Question "Clone repo into /home/$alias/projects/? (empty = skip, e.g. 'vdole')" -Default '').ToLower().Trim()
    }
    if ($repo -and $repo -notmatch '^[a-z][a-z0-9_-]{1,30}$') {
        throw "Invalid repo name: '$repo'"
    }

    $confirm = Ask -Question "Create dev '$alias' ($fullName <$email>)$(if($repo){" + clone $repo"})? [y/N]" -Default 'N'
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Cancelled." -ForegroundColor DarkGray
        return
    }

    # 1. Generate SSH keypair on PC
    $keyDir = Join-Path $KEYS_CLIENT_ROOT $alias
    if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir -Force | Out-Null }
    $keyPath = Join-Path $keyDir 'id_ed25519'
    if (Test-Path $keyPath) { throw "Key already exists at $keyPath — refusing to overwrite" }

    Write-Host "[ssh-keygen] generating $keyPath ..." -ForegroundColor DarkGray
    & ssh-keygen -t ed25519 -f $keyPath -N '""' -C "$alias@moscow_my" -q
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed" }

    $pubKey = Get-Content "$keyPath.pub" -Raw
    $fp = (& ssh-keygen -lf $keyPath -E sha256) -split '\s+' | Select-Object -Index 1

    # 2a. Allocate port block + provision nginx + cert (only if repo is being cloned)
    $portBase = 0
    if ($repo) {
        $portBase = Get-NextPortBlock
        Write-Host "[port] allocated 10-block: API=$portBase HMR=$($portBase+1) BOT_TG=$($portBase+2) BOT_MAX=$($portBase+4)" -ForegroundColor DarkGray
        try {
            New-NginxConfForDev -Alias $alias -PortBase $portBase
        } catch {
            Write-Host "[nginx] failed: $_" -ForegroundColor Yellow
        }
    }

    # 2b. Create user on server (uploads pubkey via stdin)
    Write-Host "[server] creating user $alias ..." -ForegroundColor DarkGray
    $pubKeyEscaped = $pubKey.Trim().Replace("'", "'\''")
    & ssh $SSH_HOST "sudo bash $SERVER_SKILL_DIR/add-user.sh '$alias' '$($fullName.Replace("'","'\''"))' '$email' '$pubKeyEscaped' '$repo' '$portBase'"
    if ($LASTEXITCODE -ne 0) { throw "add-user.sh failed" }

    # 3. Sync skills to /opt/claude-shared/ (if first dev or allowlist changed)
    Sync-Skills -Alias 'all'

    # 4. Write local metadata
    $aliasDir = Join-Path $DEVELOPERS_DIR $alias
    if (-not (Test-Path $aliasDir)) { New-Item -ItemType Directory -Path $aliasDir -Force | Out-Null }

    $info = @{
        alias       = $alias
        full_name   = $fullName
        email       = $email
        created_at  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
        status      = 'active'
        ssh_key_fp  = $fp
        ssh_key_path = $keyPath
    }
    ($info | ConvertTo-Json -Depth 5) | Set-Content -Path (Join-Path $aliasDir 'info.json') -Encoding UTF8

    # 5. Generate onboarding text
    $onboarding = @"
# Onboarding for $alias

Welcome to VDole dev environment.

## Your access

- Server: ``moscow_my``, host alias in your ``~/.ssh/config``
- SSH port: ``53847`` (public, IPv4)
- Username: ``$alias``
- Private key: keep secure on your machine only.

## ~/.ssh/config entry

``````
Host vdole-moscow
    HostName <ip>
    Port 53847
    User $alias
    IdentityFile ~/.ssh/vdole_moscow
``````

## Clone VDole

``````bash
git clone vdole-moscow:/srv/git/VDole.git
cd VDole
git config user.name "$fullName"
git config user.email "$email"
``````

## Push workflow

- Your branches: ``git push origin $alias/feature-name``
- ``main``, ``master``, ``release/*``, ``prod``, ``production`` — push blocked by hook. Open PR on GitHub instead.
- All pushes mirrored to GitHub automatically via internal bot.

## Claude Code

Pre-configured. Just run:

``````bash
claude
``````

Skills/hooks/CLAUDE.md are shared (read-only). Your sessions and projects are private to your home.

## Questions

Ping ssv (chief) directly.
"@
    $onboarding | Set-Content -Path (Join-Path $aliasDir 'onboarding.md') -Encoding UTF8

    # 6. SSH_KEYS_INVENTORY.md row
    if (Test-Path $SSH_INVENTORY_PATH) {
        $row = "| $alias | $fullName | $email | ed25519 | $fp | $(Get-Date -Format 'yyyy-MM-dd') | active |"
        Add-Content -Path $SSH_INVENTORY_PATH -Value $row -Encoding UTF8
    } else {
        Write-Host "[warn] SSH_KEYS_INVENTORY.md not found — create manually at $SSH_INVENTORY_PATH" -ForegroundColor Yellow
    }

    # 7. Print summary
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "Dev '$alias' created. Onboarding text:" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host $onboarding
    Write-Host ""
    Write-Host "Private key path (send to dev via secure channel):" -ForegroundColor Yellow
    Write-Host "  $keyPath"
    Write-Host ""
}

function Cmd-Del {
    param([string]$Alias)
    if (-not $Alias) { throw "Usage: dev.ps1 del <alias>" }
    Sync-LibToServer

    $existing = & ssh $SSH_HOST "id -u $Alias 2>/dev/null"
    if ($LASTEXITCODE -ne 0) { throw "No such dev: $Alias" }

    $confirm = Ask -Question "DELETE dev '$Alias' (archive home, then userdel -r). Type the alias to confirm" -Default ''
    if ($confirm -ne $Alias) {
        Write-Host "Cancelled (confirmation did not match)." -ForegroundColor DarkGray
        return
    }

    $today = Get-Date -Format 'yyyy-MM-dd'
    $archiveDir = Join-Path $DEVELOPERS_DIR "$Alias\_archive\$today"
    if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null }

    # 1. Server-side: kill, tar, leave archives in /tmp/dev-del-<alias>-<today>/
    Write-Host "[server] archiving and deleting $Alias ..." -ForegroundColor DarkGray
    & ssh $SSH_HOST "sudo bash $SERVER_SKILL_DIR/del-user.sh '$Alias' '$today'"
    if ($LASTEXITCODE -ne 0) { throw "del-user.sh failed" }

    # 2. scp archives back
    $remotePath = "/tmp/dev-del-$Alias-$today"
    Write-Host "[scp] downloading archives to $archiveDir ..." -ForegroundColor DarkGray
    & scp -q -r "${SSH_HOST}:$remotePath/*" $archiveDir
    if ($LASTEXITCODE -ne 0) { throw "scp of archives failed" }

    # 3. Cleanup on server
    & ssh $SSH_HOST "sudo rm -rf $remotePath"

    # 3a. Remove nginx conf + cert + webroot for dev
    Remove-NginxConfForDev -Alias $Alias

    # 4. Update local meta
    $infoPath = Join-Path $DEVELOPERS_DIR "$Alias\info.json"
    if (Test-Path $infoPath) {
        $info = Get-Content $infoPath -Raw | ConvertFrom-Json
        $info | Add-Member -NotePropertyName 'archived_at' -NotePropertyValue (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz') -Force
        $info | Add-Member -NotePropertyName 'status' -NotePropertyValue 'archived' -Force
        ($info | ConvertTo-Json -Depth 5) | Set-Content -Path $infoPath -Encoding UTF8
    }

    # 5. SSH_KEYS_INVENTORY.md → mark REVOKED (append a note, don't rewrite)
    if (Test-Path $SSH_INVENTORY_PATH) {
        Add-Content -Path $SSH_INVENTORY_PATH -Value "| $Alias | (revoked $today) | — | — | — | — | REVOKED |" -Encoding UTF8
    }

    Write-Host ""
    Write-Host "Dev '$Alias' deleted. Archives:" -ForegroundColor Green
    Write-Host "  $archiveDir"
}

function Sync-Skills {
    param([string]$Alias = 'all')
    Sync-LibToServer

    $allow = Read-Allowlist
    $globalSkills = @($allow.global)
    $skillsRoot = Join-Path $env:USERPROFILE '.claude\skills'

    Write-Host "[sync-skills] uploading $(($globalSkills | Measure-Object).Count) global skills to /opt/claude-shared/skills/ ..." -ForegroundColor DarkGray
    & ssh $SSH_HOST "sudo mkdir -p /opt/claude-shared/skills && sudo chown `$(id -u):`$(id -g) /opt/claude-shared/skills"

    foreach ($s in $globalSkills) {
        $local = Join-Path $skillsRoot $s
        if (-not (Test-Path $local)) {
            Write-Host "  [skip] $s — not present in $skillsRoot" -ForegroundColor Yellow
            continue
        }
        # Resolve symlinks (e.g. code-review → ~/.agents/skills/code-review/)
        $resolved = (Resolve-Path $local).Path

        Write-Host "  $s" -ForegroundColor DarkGray
        & ssh $SSH_HOST "sudo rm -rf /opt/claude-shared/skills/$s"
        & scp -q -r $resolved "${SSH_HOST}:/opt/claude-shared/skills/$s"
        if ($LASTEXITCODE -ne 0) { Write-Host "    [warn] scp failed for $s" -ForegroundColor Yellow }
    }

    # Lock down
    & ssh $SSH_HOST "sudo chown -R root:root /opt/claude-shared/skills && sudo chmod -R u=rwX,go=rX /opt/claude-shared/skills"
    Write-Host "[sync-skills] done" -ForegroundColor Green
}

function Cmd-Bootstrap {
    Sync-LibToServer
    Write-Host "[bootstrap] running bootstrap-server.sh ..." -ForegroundColor DarkGray
    & ssh $SSH_HOST "sudo bash $SERVER_SKILL_DIR/bootstrap-server.sh"
    if ($LASTEXITCODE -ne 0) { throw "bootstrap-server.sh failed" }
    Write-Host "[bootstrap] OK" -ForegroundColor Green
}

function Cmd-Help {
    Write-Host ""
    Write-Host "/dev — manage developers on moscow_my (chief-only)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor Yellow
    Write-Host "  /dev                          List all devs (default)"
    Write-Host "  /dev list                     List all devs"
    Write-Host "  /dev <alias>                  Show details for one dev"
    Write-Host "  /dev show <alias>             Show details for one dev"
    Write-Host "  /dev add                      Interactive: create new dev (alias, name, email)"
    Write-Host "                                + SSH key + auto-bootstrap on first run"
    Write-Host "  /dev del <alias>              Kill processes, archive home/projects/claude data,"
    Write-Host "                                userdel -r (with confirmation)"
    Write-Host "  /dev sync-skills [<alias>|all]   Re-sync allowlisted skills into"
    Write-Host "                                   /opt/claude-shared/skills/"
    Write-Host "  /dev bootstrap                Manual server bootstrap (usually auto on first 'add')"
    Write-Host "  /dev help                     This screen"
    Write-Host ""
    Write-Host "FILES" -ForegroundColor Yellow
    Write-Host "  Allowlist:  ~/.claude/developers/skills_allowlist.json"
    Write-Host "  Per-dev:    ~/.claude/developers/<alias>/{info.json, onboarding.md, _archive/}"
    Write-Host "  SSH keys:   D:\Data\Backup\Ubuntu-Servers\moscow_my\keys-client\<alias>\"
    Write-Host "  Server lib: /opt/dev-skill/  (synced from ~/.claude/skills/dev/lib/)"
    Write-Host ""
    Write-Host "GUARDS" -ForegroundColor Yellow
    Write-Host "  Identity:   USERNAME=ssv555 OR COMPUTERNAME=PC-SKY (else: refused)"
    Write-Host "  Bootstrap:  idempotent — marker /opt/dev-skill/.bootstrap-ok"
    Write-Host "  Skills:     devs cannot add/edit — ~/.claude/skills is a root-owned symlink"
    Write-Host ""
}

# ============================================================================
# Main
# ============================================================================

Assert-Chief

switch ($Subcommand.ToLower()) {
    'list'         { Cmd-List }
    ''             { Cmd-List }
    'show'         { Cmd-Show -Alias $Arg1 }
    'add'          { Cmd-Add -PreAlias $Arg1 -RepoName $Arg2 }
    'del'          { Cmd-Del -Alias $Arg1 }
    'sync-skills'  {
        $a = if ($Arg1) { $Arg1 } else { 'all' }
        Sync-Skills -Alias $a
    }
    'bootstrap'    { Cmd-Bootstrap }
    'help'         { Cmd-Help }
    '--help'       { Cmd-Help }
    '-h'           { Cmd-Help }
    default {
        # Maybe <alias> form: /dev <alias> → show
        if ($Subcommand -match '^[a-z][a-z0-9_]{2,15}$') {
            Cmd-Show -Alias $Subcommand
        } else {
            Write-Host "Unknown subcommand: $Subcommand" -ForegroundColor Red
            Cmd-Help
            exit 1
        }
    }
}
