# Backup production DB (Moscow) and restore to local dev PostgreSQL
# Global script - runs from any project directory with .ssh/id_rsa and .env.development
# Usage (from project root):
#   powershell.exe -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\ahk\prod-to-dev.ps1
#   powershell.exe -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\ahk\prod-to-dev.ps1 -SkipBackup
#   powershell.exe -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\ahk\prod-to-dev.ps1 -UseLatestLocal

[CmdletBinding()]
param(
    [switch]$SkipBackup,       # Skip SSH backup, use latest dump on server
    [switch]$UseLatestLocal    # Skip SSH + SCP, use latest .dump in .tmp/
)

$ErrorActionPreference = "Stop"
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# --- Config (derived from current working directory) ---
$ProjectRoot = Get-Location | Select-Object -ExpandProperty Path
$SshKey = Join-Path $ProjectRoot ".ssh\id_rsa"
$SshHost = "root@195.2.75.212"
$SshPort = 1022
$RemoteBackupScript = "/var/www/iamrich.it-joy.ru/scripts/deploy/01-backup-db.sh"
$RemoteBackupDir = "/var/backups/iamrich"
$LocalTmpDir = Join-Path $ProjectRoot ".tmp"
$EnvFile = Join-Path $ProjectRoot ".env.development"
$SshOpts = @("-i", $SshKey, "-p", $SshPort, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes")

# --- Helpers ---
function Write-Step($step, $total, $msg) {
    Write-Host "`n[prod-to-dev] " -ForegroundColor Cyan -NoNewline
    Write-Host "Step ${step}/${total}: ${msg}" -ForegroundColor White
}

function Write-Ok($msg) {
    Write-Host "  [OK] " -ForegroundColor Green -NoNewline
    Write-Host $msg
}

function Write-Fail($msg) {
    Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
    Write-Host $msg
}

function Write-Warn($msg) {
    Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $msg
}

function Get-PgBinPath {
    $pgBase = "C:\Program Files\PostgreSQL"
    if (-not (Test-Path $pgBase)) { return $null }
    $versions = Get-ChildItem $pgBase -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\pg_restore.exe") } |
        Sort-Object { [int]$_.Name } -Descending
    if ($versions.Count -eq 0) { return $null }
    return @{ Path = (Join-Path $versions[0].FullName "bin"); Version = $versions[0].Name }
}

function Parse-DatabaseUrl([string]$Url) {
    if ($Url -match '^postgres(ql)?://([^:]+):([^@]+)@([^:]+):(\d+)/(.+)$') {
        $host_ = if ($Matches[4] -eq '0.0.0.0') { 'localhost' } else { $Matches[4] }
        return @{
            User     = $Matches[2]
            Password = $Matches[3]
            Host     = $host_
            Port     = $Matches[5]
            Database = $Matches[6]
        }
    }
    return $null
}

# --- Step 1: Validate prerequisites ---
if ($UseLatestLocal) { $totalSteps = 3 } else { $totalSteps = 4 }
$step = 1

Write-Step $step $totalSteps "Validating prerequisites..."

# SSH key
if (-not $UseLatestLocal) {
    if (-not (Test-Path $SshKey)) {
        Write-Fail "SSH key not found: $SshKey"
        exit 1
    }
    Write-Ok "SSH key found"
}

# .env.development
if (-not (Test-Path $EnvFile)) {
    Write-Fail ".env.development not found: $EnvFile"
    exit 1
}

$dbUrl = (Get-Content $EnvFile | Where-Object { $_ -match '^DATABASE_URL=' }) -replace '^DATABASE_URL=', ''
$db = Parse-DatabaseUrl $dbUrl
if (-not $db) {
    Write-Fail "Cannot parse DATABASE_URL from .env.development"
    exit 1
}
$dbInfo = "$($db.Database)@$($db.Host):$($db.Port)"
Write-Ok "DATABASE_URL parsed - $dbInfo"

# PostgreSQL
$pg = Get-PgBinPath
if (-not $pg) {
    Write-Fail "PostgreSQL not found in C:\Program Files\PostgreSQL\"
    exit 1
}
$pgRestore = Join-Path $pg.Path "pg_restore.exe"
$pgPsql = Join-Path $pg.Path "psql.exe"
$pgVer = $pg.Version
Write-Ok "PostgreSQL $pgVer found"

# .tmp directory
if (-not (Test-Path $LocalTmpDir)) {
    New-Item -ItemType Directory -Path $LocalTmpDir -Force | Out-Null
    Write-Ok "Created .tmp/ directory"
}

# --- Step 2: Backup + download from production (single SSH + SCP) ---
if (-not $UseLatestLocal) {
    $step++
    if ($SkipBackup) {
        Write-Step $step $totalSteps "Connecting and finding latest dump..."
    } else {
        Write-Step $step $totalSteps "Backup + download from production..."
    }

    # Single SSH: backup (optional) + get latest dump path
    if ($SkipBackup) {
        $sshCmd = "ls -t $RemoteBackupDir/backup_*.dump 2>/dev/null | head -1"
    } else {
        $sshCmd = "bash $RemoteBackupScript --force >/dev/null 2>&1 && ls -t $RemoteBackupDir/backup_*.dump 2>/dev/null | head -1"
    }

    Write-Host "  [..] SSH..." -ForegroundColor DarkGray -NoNewline
    $ErrorActionPreference = "Continue"
    $remoteFile = & ssh.exe @SshOpts $SshHost $sshCmd 2>&1
    $ErrorActionPreference = "Stop"
    Write-Host "`r" -NoNewline

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "SSH failed: $remoteFile"
        exit 1
    }

    $remoteFile = ($remoteFile | Out-String).Trim()
    if (-not $remoteFile -or $remoteFile -notmatch 'backup_.*\.dump$') {
        Write-Fail "No backup files found on server"
        exit 1
    }

    $dumpFilename = Split-Path $remoteFile -Leaf
    $localDumpFile = Join-Path $LocalTmpDir $dumpFilename

    if (-not $SkipBackup) { Write-Ok "Backup created" }

    # SCP download
    Write-Host "  [..] Downloading..." -ForegroundColor DarkGray -NoNewline
    $ErrorActionPreference = "Continue"
    & scp.exe -i $SshKey -P $SshPort -o StrictHostKeyChecking=accept-new "${SshHost}:${remoteFile}" $localDumpFile 2>&1
    $ErrorActionPreference = "Stop"
    Write-Host "`r" -NoNewline

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "SCP download failed"
        exit 1
    }

    $fileSize = [math]::Round((Get-Item $localDumpFile).Length / 1KB)
    Write-Ok "$dumpFilename - ${fileSize} KB"
} else {
    # Use latest local dump
    $localDumps = Get-ChildItem $LocalTmpDir -Filter "backup_*.dump" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    if ($localDumps.Count -eq 0) {
        Write-Fail "No dump files in .tmp/ - run without -UseLatestLocal first"
        exit 1
    }
    $localDumpFile = $localDumps[0].FullName
    $dumpFilename = $localDumps[0].Name
    $fileSize = [math]::Round($localDumps[0].Length / 1KB)
    Write-Ok "Using local: $dumpFilename - ${fileSize} KB"
}

# --- Step 4: Restore to local dev DB ---
$step++
Write-Step $step $totalSteps "Restoring database..."

$env:PGPASSWORD = $db.Password

$ErrorActionPreference = "Continue"
$restoreOutput = & $pgRestore `
    -h $db.Host `
    -p $db.Port `
    -U $db.User `
    -d $db.Database `
    --clean `
    --if-exists `
    --no-owner `
    --no-privileges `
    $localDumpFile 2>&1
$ErrorActionPreference = "Stop"

$restoreText = $restoreOutput | Out-String
$hasErrors = $restoreText -match '(?m)^.*ERROR:.*$'

if ($LASTEXITCODE -ne 0 -and $hasErrors) {
    Write-Fail "Restore failed with errors:"
    # Show only ERROR lines
    $restoreText -split "`n" | Where-Object { $_ -match 'ERROR:' } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Red
    }
    exit 1
} elseif ($LASTEXITCODE -ne 0) {
    Write-Ok "Restored (with non-fatal warnings)"
} else {
    Write-Ok "Restored successfully"
}

# --- Step 5: Verify table row counts ---
$step++
Write-Step $step $totalSteps "Verifying tables..."

$tables = @("users", "expenses", "expenses_categories", "expenses_periodicals", "user_families", "donation_pays")

foreach ($table in $tables) {
    $ErrorActionPreference = "Continue"
    $count = & $pgPsql -h $db.Host -p $db.Port -U $db.User -d $db.Database -t -A -c "SELECT COUNT(*) FROM $table" 2>&1
    $ErrorActionPreference = "Stop"
    $count = ($count | Out-String).Trim()
    $padded = $table.PadRight(24)
    Write-Host "  $padded" -ForegroundColor Gray -NoNewline
    Write-Host $count -ForegroundColor White
}

# --- Done ---
$env:PGPASSWORD = $null
$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed.ToString('mm\:ss')

Write-Host "`n[prod-to-dev] " -ForegroundColor Cyan -NoNewline
Write-Host "Done! " -ForegroundColor Green -NoNewline
Write-Host "$elapsed" -ForegroundColor Gray
