# Claude Code PreToolUse hook - blocks dangerous patterns in Bash commands
# Exit code 2 = block tool call and show stderr to model
# Exit code 0 = allow tool call
#
# IMPORTANT: When calling from settings.json, use this pattern:
#   & script.ps1; exit $LASTEXITCODE
# Direct call (& $f) or dot-source (. $f) do NOT propagate exit codes!

$input_json = [Console]::In.ReadToEnd()

try {
    $data = $input_json | ConvertFrom-Json
    $command = $data.tool_input.command
} catch {
    exit 0
}

if (-not $command) { exit 0 }

function Write-BlockLog($reason, $blockedCommand) {
    try {
        $logFile = Join-Path $PSScriptRoot 'hook-blocks.log'
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry = "[$timestamp] BLOCKED: $reason`n  Command: $blockedCommand`n"
        Add-Content -Path $logFile -Value $entry -Encoding UTF8
    } catch {
        # Logging is best-effort
    }
}

function Show-BlockNotification($title, $message, $blockedCommand) {
    try {
        $script = Join-Path $PSScriptRoot 'show-notification.ps1'
        $safeCmd = ($blockedCommand -replace '"', "'")
        $a = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Title `"$title`" -Message `"$message`" -Command `"$safeCmd`""
        Start-Process powershell -ArgumentList $a
    } catch {
        # Notification is optional - don't let it prevent blocking
    }
}

# Block "nul" as standalone word (not "null", "nullable", etc.)
if ($command -match '(?i)(?<![a-z])nul(?![a-z])') {
    [Console]::Error.WriteLine("BLOCKED: 'nul' is a reserved Windows device name that creates undeletable files. This command is FORBIDDEN. You MUST find an alternative. Use '> .tmp/null' or '2>/dev/null' instead of '> nul'. NEVER attempt to delete or fix nul-related issues yourself - tell the user.")
    Write-BlockLog "'nul' reserved device name" $command
    Show-BlockNotification "Claude Code BLOCKED" "Blocked 'nul' (reserved device name)" $command
    exit 2
}

# Block elevated privileges
if ($command -match '(?i)-Verb\s+RunAs') {
    [Console]::Error.WriteLine("BLOCKED: Elevated privileges (-Verb RunAs) are FORBIDDEN. Running commands as admin has previously DELETED user .env files. You MUST NOT use elevated privileges to fix your own mistakes. STOP and tell the user about the problem instead.")
    Write-BlockLog "Elevated privileges (-Verb RunAs)" $command
    Show-BlockNotification "Claude Code BLOCKED" "Blocked elevated privileges (-Verb RunAs)" $command
    exit 2
}

# --- Dangerous commands: ask user via dialog ---

$dangerousPatterns = @(
    @{ Pattern = '(?i)\bgit\s+(commit|push|reset\s+--hard|checkout\s+[\.\-]|restore\s+[\.\-]|clean\s+-[fd]|branch\s+-[dD])'; Reason = 'Git destructive/push/commit' },
    @{ Pattern = '(?i)\brm\s+-(rf|fr|r)\b'; Reason = 'Recursive delete (rm -rf)' },
    @{ Pattern = '(?i)\bdel\s+/'; Reason = 'Windows delete (del)' },
    @{ Pattern = '(?i)\brmdir\b'; Reason = 'Remove directory (rmdir)' },
    @{ Pattern = '(?i)\bRemove-Item\b'; Reason = 'PowerShell Remove-Item' },
    @{ Pattern = '(?i)\bmv\s+.*\s+'; Reason = 'Move/rename (mv)' },
    @{ Pattern = '(?i)\bMove-Item\b'; Reason = 'PowerShell Move-Item' },
    @{ Pattern = '(?i)\bRename-Item\b'; Reason = 'PowerShell Rename-Item' }
)

foreach ($dp in $dangerousPatterns) {
    if ($command -match $dp.Pattern) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $shortCmd = if ($command.Length -gt 200) { $command.Substring(0, 200) + '...' } else { $command }
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Claude wants to run a DANGEROUS command:`n`n$shortCmd`n`nReason: $($dp.Reason)`n`nAllow?",
                "Claude Code - Confirm dangerous command",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-BlockLog "ALLOWED by user: $($dp.Reason)" $command
                exit 0
            } else {
                [Console]::Error.WriteLine("BLOCKED by user: $($dp.Reason). Command was not allowed. Ask the user what to do instead.")
                Write-BlockLog "DENIED by user: $($dp.Reason)" $command
                Show-BlockNotification "Claude Code DENIED" "User denied: $($dp.Reason)" $command
                exit 2
            }
        } catch {
            # If dialog fails, block by default
            [Console]::Error.WriteLine("BLOCKED: $($dp.Reason) - could not show confirmation dialog. Command blocked for safety.")
            Write-BlockLog "BLOCKED (dialog failed): $($dp.Reason)" $command
            exit 2
        }
    }
}

# Allow everything else
exit 0
