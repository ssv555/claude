# Claude Code PreToolUse hook — blocks Edit/Write on sealed module files
# Exit code 2 = block tool call and show stderr to model
# Exit code 0 = allow tool call
#
# Config: ~/.claude/sealed/*.json — one file per project
# Called from settings.json for matcher "Edit|Write"

$input_json = [Console]::In.ReadToEnd()

try {
    $data = $input_json | ConvertFrom-Json
    $toolName = $data.tool_name
    $filePath = $data.tool_input.file_path
} catch {
    exit 0
}

# Guard only Edit and Write
if ($toolName -ne 'Edit' -and $toolName -ne 'Write') { exit 0 }
if (-not $filePath) { exit 0 }

function Normalize-Path([string]$p) {
    if (-not $p) { return '' }
    $p = $p -replace '\\', '/'
    $p = $p.ToLower().TrimEnd('/')
    return $p
}

$normalizedFile = Normalize-Path $filePath
$sealedDir = Join-Path $env:USERPROFILE '.claude\sealed'

if (-not (Test-Path $sealedDir)) { exit 0 }

$configFiles = Get-ChildItem -Path $sealedDir -Filter '*.json' -ErrorAction SilentlyContinue
if (-not $configFiles) { exit 0 }

function Write-BlockLog([string]$reason, [string]$path) {
    try {
        $logFile = Join-Path $PSScriptRoot 'hook-blocks.log'
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "[$ts] SEALED BLOCKED: $reason`n  File: $path`n"
        Add-Content -Path $logFile -Value $entry -Encoding UTF8
    } catch {}
}

function Show-BlockNotification([string]$title, [string]$message) {
    try {
        $script = Join-Path $PSScriptRoot 'show-notification.ps1'
        if (-not (Test-Path $script)) { return }
        $a = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Title `"$title`" -Message `"$message`""
        Start-Process powershell -ArgumentList $a -WindowStyle Hidden
    } catch {}
}

foreach ($cfgFile in $configFiles) {
    try {
        $config = Get-Content -Path $cfgFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { continue }

    if (-not $config.root) { continue }
    $projRoot = Normalize-Path $config.root

    if (-not $normalizedFile.StartsWith($projRoot + '/')) { continue }

    $relPath = $normalizedFile.Substring($projRoot.Length + 1)

    if (-not $config.groups) { continue }

    foreach ($groupName in $config.groups.PSObject.Properties.Name) {
        $group = $config.groups.$groupName
        if (-not $group.sealed) { continue }
        if (-not $group.files) { continue }

        foreach ($f in $group.files) {
            $normalizedGroupFile = Normalize-Path $f
            if ($relPath -eq $normalizedGroupFile) {
                $desc = $group.description
                $msg = "BLOCKED: File '$relPath' is in sealed module group '$groupName' ($desc). " +
                       "This file is protected from AI edits. Ask the user to run '/unseal $groupName' " +
                       "to temporarily unseal, then '/seal $groupName' after edits."
                [Console]::Error.WriteLine($msg)
                Write-BlockLog "group=$groupName" $relPath
                Show-BlockNotification "Sealed Module BLOCKED" "$groupName`: $relPath"
                exit 2
            }
        }
    }
}

exit 0
