; Автопереключение раскладки в Cursor
; F13 привязан в Cursor keybindings к workbench.action.terminal.focus
; Это focus-only (НЕ toggle) — всегда открывает/фокусит терминал

#SingleInstance Force

global PreviousLayout := 0

; Группа поддерживаемых редакторов — все хоткеи ниже работают в этих IDE
GroupAdd, CodeEditors, ahk_exe Cursor.exe
GroupAdd, CodeEditors, ahk_exe Code.exe
GroupAdd, CodeEditors, ahk_exe VSCodium.exe
GroupAdd, CodeEditors, ahk_exe webstorm64.exe
GroupAdd, CodeEditors, ahk_exe Trae.exe

#IfWinActive ahk_group CodeEditors

; Alt+Z - переход на терминал, переключение на английскую раскладку
$!z::
{
    PreviousLayout := GetCurrentLayout()
    Send {F13}
    Sleep, 100
    SwitchToEnglish()
    return
}

; Alt+X - переход на редактор, возврат предыдущей раскладки
$!x::
{
    Send ^1
    Sleep, 50
    if (PreviousLayout != 0)
    {
        SwitchToLayout(PreviousLayout)
    }
    return
}

; === Быстрые команды для терминала ===

FocusTerminalAndType(command)
{
    global PreviousLayout
    PreviousLayout := GetCurrentLayout()
    Send {F13}
    Sleep, 150
    SwitchToEnglish()
    Sleep, 100
    Send {Escape}
    Sleep, 50
    SendInput {Raw}%command%
}

; Alt+0 - запуск dev:laptop
$!0::
{
    FocusTerminalAndType("bun run dev:laptop")
    return
}

; Alt+1 - запуск dev:browser
$!1::
{
    FocusTerminalAndType("bun run dev:browser")
    return
}

; Alt+2 - запуск db:push
$!2::
{
    FocusTerminalAndType("bun run db:push")
    return
}

; Alt+3 - запуск run_all_update.cmd
$!3::
{
    FocusTerminalAndType("run_all_update.cmd")
    return
}

; Alt+4 - git pull в глобальных скиллах
$!4::
{
    FocusTerminalAndType("pushd %USERPROFILE%\.claude\skills && git pull && popd")
    return
}

; Alt+5 - git add + commit + push
$!5::
{
    FocusTerminalAndType("git add -A && git commit -m ""commit"" && git push")
    return
}

; Alt+6 - git reset hard to origin/main
$!6::
{
    FocusTerminalAndType("git fetch origin && git reset --hard origin/main")
    return
}

; Alt+7 - push AHK scripts to git
$!7::
{
    FocusTerminalAndType("powershell.exe -ExecutionPolicy Bypass -File """ . A_ScriptDir . "\push-ahk.ps1""")
    return
}

; Alt+8 - push changelog entries to prod
$!8::
{
    FocusTerminalAndType("bun run changelog:push-to-prod")
    return
}

; Alt+9 - prod-db-to database sync
$!9::
{
    FocusTerminalAndType("powershell.exe -ExecutionPolicy Bypass -File """ . A_ScriptDir . "\prod-db-to.ps1""")
    return
}

; === Docs (Starlight) ===

; Alt+D - dev:docs
$!d::
{
    FocusTerminalAndType("bun run dev:docs")
    return
}

; Alt+B - build:docs
$!b::
{
    FocusTerminalAndType("bun run build:docs")
    return
}

; Alt+P - preview:docs
$!p::
{
    FocusTerminalAndType("bun run preview:docs")
    return
}

; Alt+H - help
$!h::
{
    Gui, Help:Destroy
    Gui, Help:+AlwaysOnTop +ToolWindow
    Gui, Help:Font, s12 bold, Consolas
    Gui, Help:Add, Text, , % "Cursor Hotkeys:`n"
        . "`nFocus && Layout:"
        . "`n  Alt+Z  - Focus terminal + switch to EN layout"
        . "`n  Alt+X  - Focus editor + restore previous layout"
        . "`n"
        . "`nQuick Commands (terminal + auto-type):"
        . "`n  Alt+0  - bun run dev:laptop"
        . "`n  Alt+1  - bun run dev:browser"
        . "`n  Alt+2  - bun run db:push"
        . "`n  Alt+3  - run_all_update.cmd"
        . "`n  Alt+4  - git pull in global skills"
        . "`n  Alt+5  - git add + commit + push"
        . "`n  Alt+6  - git reset --hard origin/main"
        . "`n  Alt+7  - push AHK scripts to git"
        . "`n  Alt+8  - bun run changelog:push-to-prod"
        . "`n  Alt+9  - prod-db-to (sync prod DB to local)"
        . "`n"
        . "`nDocs (Starlight):"
        . "`n  Alt+D  - bun run dev:docs"
        . "`n  Alt+B  - bun run build:docs"
        . "`n  Alt+P  - bun run preview:docs"
        . "`n"
        . "`nHelp:"
        . "`n  Alt+H  - Show this help"
    Gui, Help:Font, s11
    Gui, Help:Add, Button, w120 gHelpGuiClose Default, OK
    Gui, Help:Show, , Cursor AutoHotkey Hotkeys
    return
}

HelpGuiClose:
HelpGuiEscape:
{
    Gui, Help:Destroy
    return
}

#IfWinActive

; === Вспомогательные функции ===

GetCurrentLayout()
{
    ThreadID := DllCall("GetWindowThreadProcessId", "Ptr", WinExist("A"), "Ptr", 0)
    Layout := DllCall("GetKeyboardLayout", "Ptr", ThreadID, "Ptr")
    return Layout
}

SwitchToEnglish()
{
    PostMessage, 0x50, 0, 0x04090409,, A
}

SwitchToEnglishForce()
{
    ; Читаем из реестра какой хоткей для переключения: 1=Alt+Shift, 2=Ctrl+Shift
    RegRead, lhk, HKEY_CURRENT_USER, Keyboard Layout\Toggle, Language Hotkey
    if (lhk = 2)
        SendInput {LCtrl down}{LShift down}{LShift up}{LCtrl up}
    else
        SendInput {LAlt down}{LShift down}{LShift up}{LAlt up}
}

SwitchToLayout(LocaleID)
{
    PostMessage, 0x50, 0, LocaleID,, A
}
