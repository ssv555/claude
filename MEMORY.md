# Global Memory

## User Preferences
- **Language**: Always respond in Russian (ru).

## Critical Rules
- **Conserve tokens**: Be concise in responses, avoid unnecessary verbosity.
- **Documentation First**: For unfamiliar tech/APIs, check docs FIRST (WebSearch or Task tool). NEVER guess.
- **No Hardcoding**: Never hardcode magic values -- extract to named constants.
- **No truncated URLs**: Always provide FULL URLs with domain, not partial paths.

## Code Standards
- Always prioritize quality, safety, stability, decomposition, and best programming patterns.
- Always update project documentation when making changes.
- Always fix ALL errors and warnings -- leave zero.

## Code Quality
- **Single Responsibility**: one function/unit = one task. If description needs "and" -- split.
- **Pure functions preferred**: minimize side effects, return values instead of mutating state.
- **Early returns**: avoid deep nesting -- validate and exit early.
- **Naming**: variables/functions describe intent (`GetUserBalance`, not `GetData`). Booleans: `Is/Has/Can/Should` prefix.
- **Constants over magic values**: extract repeated strings/numbers to named constants.
- **Error handling**: always handle errors at boundaries. Never swallow exceptions silently.
- **File limits**: Files >500 lines -> decompose.
- **Avoid over-engineering**: No extra features. Helpers only for >=2 uses. 3 similar lines > premature abstraction.

## Security
- **Secrets**: never log tokens, passwords, or session IDs.

## Documentation Style
- Docs = REFERENCE (structure, patterns), not REPORT.
- Good: `## Auth Flow`, `Session stored in cookie`
- Bad: `## Refactoring Results`, `Reduced from 842 to 200 lines`

## Windows Environment (Win10 Pro)
- **NEVER use "nul"**: Creates undeletable files on Windows. Forbidden in any form (redirection, path, argument). Use `> .tmp/null` or `2>/dev/null` instead. Удаление: `Remove-Item`, `del` НЕ работают. Два рабочих способа: **(1) PowerShell нативно**: `[IO.File]::Delete('\\?\<full-path>\nul')` -- ТОЛЬКО из PowerShell напрямую (через `-File .ps1`), НЕ через Git Bash (bash искажает `\\?\` в `\\.\`). **(2) Git Bash**: `rm "path/to/nul"` (MSYS2 не знает про зарезервированные имена). Ref: `iamrich/scripts/win-safety/remove-nul.ps1`.
- **ASCII only in scripts**: Never use non-ASCII characters (em dash, smart quotes, etc.) in `.ps1`, `.cmd`, `.bat`, `.sh` files. Use ASCII equivalents: `--`, `'`, `"`.
- **Bash = Git Bash**: Eats `$` variables. NEVER `powershell.exe -Command "..."` with `$variables` -- create `.ps1` in scratchpad, run via `-File`. Simple Windows commands: `cmd.exe /c "command"`. File copies: `cp` (Git Bash), NOT `copy`. Paths with spaces: single quotes, NOT double quotes.
- **PowerShell exit codes in hooks**: `exit N` does NOT propagate via `& $f` or `. $f`. The ONLY working pattern: `& script.ps1; exit $LASTEXITCODE`

## Global Paths
| What | Path |
|------|------|
| Claude Config (git repo: skills, agents, AHK, settings, memory) | `%USERPROFILE%\.claude\` → `github.com/ssv555/claude` |
| AHK Scripts (inside Claude repo) | `%USERPROFILE%\.claude\ahk\` |
| Windows Startup | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\` |

## Skills
- **`/context-show`** — работает. Урок: `context: fork` агенты НЕ видят `<local-command-stdout>` теги. Для доступа к системным тегам скил должен работать в основном контексте (без `context: fork`).
