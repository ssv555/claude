; Code Quality Codex — вставка свода правил в текущее окно
; Alt+Q — читает code_quality_codex.txt и вставляет через Ctrl+V
;
; Файл кодекса: %A_ScriptDir%\code_quality_codex.txt
; Редактируй его отдельно — AHK подхватит при следующем нажатии

#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

!q::
{
    codexFile := A_ScriptDir . "\code_quality_codex.txt"

    if (!FileExist(codexFile)) {
        ToolTip, code_quality_codex.txt not found!
        SetTimer, ClearToolTip, -2000
        return
    }

    FileRead, codexText, %codexFile%

    if (ErrorLevel || codexText = "") {
        ToolTip, Failed to read codex file!
        SetTimer, ClearToolTip, -2000
        return
    }

    ; Сохраняем текущий буфер
    prevClip := ClipboardAll

    ; Кладём кодекс в буфер и вставляем
    Clipboard := codexText
    ClipWait, 1
    Send ^v

    ; Восстанавливаем буфер через 500ms
    Sleep, 500
    Clipboard := prevClip
    prevClip := ""

    ToolTip, Codex inserted!
    SetTimer, ClearToolTip, -1500
    return
}

ClearToolTip:
    ToolTip
    return

; Tray
Menu, Tray, Tip, Code Quality Codex (Alt+Q)
Menu, Tray, NoStandard
Menu, Tray, Add, Insert Codex (Alt+Q), TrayInsert
Menu, Tray, Add,
Menu, Tray, Add, Reload, TrayReload
Menu, Tray, Add, Exit, TrayExit
return

TrayInsert:
    GoSub !q
    return
TrayReload:
    Reload
    return
TrayExit:
    ExitApp
    return