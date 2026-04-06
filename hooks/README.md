# Claude Code Hooks

Global hooks that run before Claude Code executes tool calls.

Location: `%USERPROFILE%\.claude\hooks\` (part of Claude git repo).

## Setup

Hooks are registered in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -Command \"& (Join-Path $env:USERPROFILE '.claude/hooks/block-dangerous.ps1'); exit $LASTEXITCODE\""
          }
        ]
      }
    ]
  }
}
```

**Important:** after changing `settings.json`, restart the Claude Code session (Ctrl+Shift+P -> Reload Window).

Path uses `$env:USERPROFILE` -- works on both PC and laptop.

## How it works

1. Claude Code calls a Bash tool
2. Before execution, the hook receives JSON on stdin with full context:
   `{"tool_name":"Bash","tool_input":{"command":"..."},...}`
3. Script parses the command and decides:
   - `exit 0` -- allow
   - `exit 2` -- block (stderr message is shown to the model)

## Exit code gotcha on Windows

**CRITICAL:** When calling a .ps1 script from `-Command`, you MUST use:

```
& script.ps1; exit $LASTEXITCODE
```

Other methods do NOT propagate exit codes:
- `& $f` -- exit code lost (process always exits 0)
- `. $f` (dot-source) -- exit code lost
- `-File script.ps1` -- works but `$env:USERPROFILE` can't be used in path

## block-dangerous.ps1

Blocks dangerous patterns in Bash commands on Windows:

| Pattern | Why |
|---------|-----|
| `nul` (standalone word) | Reserved Windows device name. `> nul` creates an undeletable file. Only removable via `[System.IO.File]::Delete('\\?\<path>\nul')` |
| `-Verb RunAs` | Elevated privileges. Previously caused deletion of `.env` files |

On block: writes error to stderr (shown to model) + shows Windows notification balloon.

## Adding new rules

Add a new `if` block in `block-dangerous.ps1`:

```powershell
if ($command -match 'your-pattern') {
    [Console]::Error.WriteLine("BLOCKED: Reason for the model")
    Show-BlockNotification "Claude Code BLOCKED" "Description"
    exit 2
}
```

**Important:** `[Console]::Error.WriteLine` must come BEFORE `Show-BlockNotification` to guarantee the error message reaches Claude Code even if the notification fails.

## prompt-optimizer.ps1

`UserPromptSubmit` hook -- intercepts user prompts, optimizes via OpenAI (gpt-4o-mini), shows comparison dialog.

**How it works:**
1. Reads prompt from stdin JSON
2. Passthrough checks: disabled? too short? `ignore ai optimisation` prefix?
3. Fires 2 parallel requests to OpenAI (HttpWebRequest + GetResponseAsync):
   - **Optimize**: rewrites prompt (English, shorter)
   - **Echo**: model repeats text + period (for exact token counting via `completion_tokens - 1`)
4. Saves original + optimized to `{project}/.tmp/prompts/`
5. Async SFTP upload to Moscow server
6. Launches WPF dialog (fullscreen, dark theme, Copy Original / Copy Optimized buttons)
7. Blocks prompt via `{"decision":"block"}` -- user copies preferred version from dialog

**Control:** `/prompt` skill or `ai prompt optimisation on|off` commands.
**State file:** `%USERPROFILE%\.claude\prompt-optimizer-state.json`

### prompt-optimizer-dialog.ps1

WPF/XAML dialog with dark theme, GridSplitter, two text panels.
Both copy buttons prepend `ignore ai optimisation` to prevent re-optimization loop.

## Troubleshooting

- Hook not firing? Check `settings.json` has `hooks` section and session was restarted
- Hook fires but doesn't block? Check exit code pattern: `& script.ps1; exit $LASTEXITCODE`
- Add debug logging: `Add-Content -Path (Join-Path $env:USERPROFILE 'hook-debug.log') -Value "msg"`
