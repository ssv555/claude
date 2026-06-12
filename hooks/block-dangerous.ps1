# Claude Code PreToolUse hook - blocks dangerous patterns in Bash commands.
# This hook is CRITICAL - it is the only thing that stops Claude from running
# `git commit`, `git push`, `rm -rf`, and other destructive commands.
# DO NOT edit the matching patterns without understanding what you are removing.
#
# Exit code 2 = block tool call and show stderr to model
# Exit code 0 = allow tool call
#
# =============================================================================
# CRITICAL - settings.json invocation requires ESCAPED dollar signs
# =============================================================================
# In ~/.claude/settings.json the hooks[].command string MUST be:
#   powershell -ExecutionPolicy Bypass -Command "& (Join-Path \$env:USERPROFILE '...'); exit \$LASTEXITCODE"
#
# Note the BACKSLASH before each dollar sign. In the JSON file itself these
# appear as "\\$env:USERPROFILE" and "\\$LASTEXITCODE" (because JSON unescapes
# \\ to a single backslash).
#
# Why the backslash is mandatory:
#   Claude Code VSCode extension (v2.1.117+) runs hook commands through bash.
#   Without the backslash, bash expands $env:USERPROFILE -> ":USERPROFILE"
#   ($env is an empty bash variable, :USERPROFILE is a literal suffix).
#   PowerShell then receives a broken path, throws CommandNotFoundException,
#   and exits with code 0. Claude Code sees exit 0 and runs the forbidden
#   command anyway - silent security failure.
#
# With the backslash: bash treats \$ as a literal $, passes it to PowerShell
# untouched, and PowerShell does its own variable expansion correctly.
#
# Regression verified 2026-04-22 - do NOT remove the escapes.
# Also applies to sealed-block.ps1 in the same settings.json.
# =============================================================================
#
# Exit code propagation pattern when invoking this script from settings.json:
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

# Remote SSH commands run on another host (e.g. Alpine) where the Windows
# Recycle Bin does not exist - the `rm` guards below are local-FS-only and must
# NOT fire for `ssh host '... rm ...'`. Exempt ONLY when the WHOLE Bash command
# is an ssh invocation (starts with `ssh <arg>`). Deliberately NOT matching
# `ssh` later in a chain: `rm secret && ssh host echo` starts with a LOCAL rm
# that must stay guarded - matching the trailing `ssh` would silently delete it
# past the bin (data-loss regression). Only the rm patterns are exempted (see
# $RemoteSafe), never git/Remove-Item/mv/del/etc.
$isRemoteSsh = $command -match '(?i)^\s*ssh\s+\S'

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

# Block elevated privileges.
# NARROW EXCEPTION: elevating `route` (Windows routing table: route add/delete/change)
# is allowed - it needs admin but touches NO files, so it can't repeat the .env-delete
# incident this guard was built for. Everything else elevated stays blocked.
# Keep this whitelist as tight as possible (one binary, networking-only).
$elevationAllow = '(?i)Start-Process\s+route\b'
if ($command -match '(?i)-Verb\s+RunAs' -and $command -notmatch $elevationAllow) {
    [Console]::Error.WriteLine("BLOCKED: Elevated privileges (-Verb RunAs) are FORBIDDEN. Running commands as admin has previously DELETED user .env files. You MUST NOT use elevated privileges to fix your own mistakes. STOP and tell the user about the problem instead.")
    Write-BlockLog "Elevated privileges (-Verb RunAs)" $command
    Show-BlockNotification "Claude Code BLOCKED" "Blocked elevated privileges (-Verb RunAs)" $command
    exit 2
}

# --- Dangerous commands: ask user via dialog ---

$dangerousPatterns = @(
    @{ Pattern = '(?i)\bgit\s+(commit|push|reset\s+--hard|checkout\s+[\.\-]|restore\s+[\.\-]|clean\s+-[fd]|branch\s+-[dD])'; Reason = 'Git destructive/push/commit' },
    @{ Pattern = '(?i)\brm\s+-(rf|fr|r)\b'; Reason = 'Recursive delete (rm -rf)'; RemoteSafe = $true },
    @{ Pattern = '(?i)\bdel\s+/'; Reason = 'Windows delete (del)' },
    @{ Pattern = '(?i)\brmdir\b'; Reason = 'Remove directory (rmdir)' },
    @{ Pattern = '(?i)\bRemove-Item\b'; Reason = 'PowerShell Remove-Item' },
    @{ Pattern = '(?i)\bmv\s+.*\s+'; Reason = 'Move/rename (mv)' },
    @{ Pattern = '(?i)\bMove-Item\b'; Reason = 'PowerShell Move-Item' },
    @{ Pattern = '(?i)\bRename-Item\b'; Reason = 'PowerShell Rename-Item' }
)

foreach ($dp in $dangerousPatterns) {
    if ($isRemoteSsh -and $dp.RemoteSafe) { continue }
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

# --- Non-recursive `rm` is FORBIDDEN: it deletes past the Recycle Bin ---
# Recursive `rm -rf|-fr|-r` is handled above (confirm dialog, bypasses the bin
# on purpose for bulk dirs like node_modules). Any other `rm` must go through
# trash.ps1 so the deletion lands in the Recycle Bin and stays recoverable.
if (-not $isRemoteSsh -and $command -match '(?i)\brm\b') {
    $trash = Join-Path $env:USERPROFILE '.claude\scripts\trash.ps1'
    [Console]::Error.WriteLine("BLOCKED: bare 'rm' is FORBIDDEN by user rules - it deletes past the Recycle Bin (unrecoverable). Delete via the trash script instead, which sends files/dirs to the Recycle Bin: pwsh -NoProfile -File `"$trash`" <path> [<path> ...]. Only bulk recursive deletes (rm -rf <dir>, e.g. node_modules) are allowed past the bin, and only via the confirmation dialog.")
    Write-BlockLog "Bare rm (use trash.ps1 -> Recycle Bin)" $command
    exit 2
}

# Allow everything else
exit 0
