; DevMode PC — Автоматизация рабочего места разработчика
; Alt+F1 — Start devMode (убить лишнее, запустить нужное, расставить по столам)
; Alt+F2 — Stop devMode (закрыть всё + kill dev ports)
; Alt+F3 — Справка
;
; Требуется: VirtualDesktopAccessor.dll в папке scripts/
; Скачать: https://github.com/Ciantic/VirtualDesktopAccessor/releases/tag/2019-windows10

#NoEnv
#SingleInstance Force
#Persistent
SetWorkingDir %A_ScriptDir%
SetTitleMatchMode, 2
DetectHiddenWindows, On
SetBatchLines, -1
CoordMode, Mouse, Screen

; ============================================================
; CONFIGURATION — Редактируй эту секцию под себя
; ============================================================

; --- Активный профиль (1, 2 или 3) ---
ACTIVE_PROFILE := 1

; --- Процессы для убийства перед запуском devMode ---
; Удали из списка то, что НЕ нужно убивать
KILL_PROCESSES := []
KILL_PROCESSES.Push("Telegram.exe")
KILL_PROCESSES.Push("TOTALCMD64.exe")
KILL_PROCESSES.Push("Taskmgr.exe")

; ============================================================
; MONITOR SETUP — Координаты твоих мониторов
; ============================================================
; Primary (DISPLAY2): 2560x1440 at X=0, Y=0 (левый)
MON1_X := 0
MON1_Y := 0
MON1_W := 2560
MON1_H := 1440

; Secondary (DISPLAY1): 1920x1200 at X=3840, Y=0 (правый)
MON2_X := 3840
MON2_Y := 0
MON2_W := 1920
MON2_H := 1200

; Высота панели задач (пикселей снизу)
TASKBAR_H := 40

; ============================================================
; PROFILE 1: Web Dev
; ============================================================
P1_NAME := "Web Dev"
P1_DESKTOPS := 2
P1_APPS := []

; Cursor IDE — Desktop 0, левая половина основного монитора
P1_APPS.Push({exe: "C:\Users\ssv55\AppData\Local\Programs\cursor\Cursor.exe"
    , args: "D:\Data\Documents\Programming\Projects\WEB\iamrich"
    , winClass: "ahk_exe Cursor.exe"
    , desktop: 0
    , position: "LEFT_PRIMARY"
    , delay: 5000})

; Chrome — Desktop 0, правая половина основного монитора
P1_APPS.Push({exe: "C:\Program Files\Google\Chrome\Application\chrome.exe"
    , args: "--new-window https://localhost:31002"
    , winClass: "ahk_exe chrome.exe"
    , desktop: 0
    , position: "RIGHT_PRIMARY"
    , delay: 3000})

; Windows Terminal — Desktop 1, полный экран на втором мониторе
P1_APPS.Push({exe: "wt.exe"
    , args: "-d D:\Data\Documents\Programming\Projects\WEB\iamrich"
    , winClass: "ahk_exe WindowsTerminal.exe"
    , desktop: 1
    , position: "FULL_SECONDARY"
    , delay: 2000})

; ============================================================
; PROFILE 2: Full-Stack Dev
; ============================================================
P2_NAME := "Full-Stack Dev"
P2_DESKTOPS := 2
P2_APPS := []

; Cursor IDE — Desktop 0, левая половина основного монитора
P2_APPS.Push({exe: "C:\Users\ssv55\AppData\Local\Programs\cursor\Cursor.exe"
    , args: "D:\Data\Documents\Programming\Projects\WEB\iamrich"
    , winClass: "ahk_exe Cursor.exe"
    , desktop: 0
    , position: "LEFT_PRIMARY"
    , delay: 5000})

; Chrome с DevTools — Desktop 0, правая половина основного монитора
P2_APPS.Push({exe: "C:\Program Files\Google\Chrome\Application\chrome.exe"
    , args: "--new-window --auto-open-devtools-for-tabs https://localhost:31002"
    , winClass: "ahk_exe chrome.exe"
    , desktop: 0
    , position: "RIGHT_PRIMARY"
    , delay: 3000})

; Windows Terminal — Desktop 1, левая половина основного монитора
P2_APPS.Push({exe: "wt.exe"
    , args: "-d D:\Data\Documents\Programming\Projects\WEB\iamrich"
    , winClass: "ahk_exe WindowsTerminal.exe"
    , desktop: 1
    , position: "LEFT_PRIMARY"
    , delay: 2000})

; DBeaver — Desktop 1, правая половина основного монитора
P2_APPS.Push({exe: "C:\Program Files\DBeaver\dbeaver.exe"
    , args: ""
    , winClass: "ahk_exe dbeaver.exe"
    , desktop: 1
    , position: "RIGHT_PRIMARY"
    , delay: 4000})

; Docker Desktop — Desktop 1, полный экран на втором мониторе
P2_APPS.Push({exe: "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    , args: ""
    , winClass: "ahk_exe Docker Desktop.exe"
    , desktop: 1
    , position: "FULL_SECONDARY"
    , delay: 5000})

; ============================================================
; PROFILE 3: Minimal
; ============================================================
P3_NAME := "Minimal"
P3_DESKTOPS := 1
P3_APPS := []

; Cursor IDE — Desktop 0, левая половина основного монитора
P3_APPS.Push({exe: "C:\Users\ssv55\AppData\Local\Programs\cursor\Cursor.exe"
    , args: "D:\Data\Documents\Programming\Projects\WEB\iamrich"
    , winClass: "ahk_exe Cursor.exe"
    , desktop: 0
    , position: "LEFT_PRIMARY"
    , delay: 5000})

; Chrome — Desktop 0, правая половина основного монитора
P3_APPS.Push({exe: "C:\Program Files\Google\Chrome\Application\chrome.exe"
    , args: "--new-window https://localhost:31002"
    , winClass: "ahk_exe chrome.exe"
    , desktop: 0
    , position: "RIGHT_PRIMARY"
    , delay: 3000})

; ============================================================
; DLL LOADING — VirtualDesktopAccessor
; ============================================================
VDA_PATH := A_ScriptDir . "\VirtualDesktopAccessor.dll"
hVDA := DllCall("LoadLibrary", "Str", VDA_PATH, "Ptr")

if (!hVDA) {
    MsgBox, 16, DevMode Error,
    (
VirtualDesktopAccessor.dll not found!
Expected: %VDA_PATH%

Download from:
https://github.com/Ciantic/VirtualDesktopAccessor/releases/tag/2019-windows10
    )
    ExitApp
}

GoToDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GoToDesktopNumber", "Ptr")
GetCurrentDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetCurrentDesktopNumber", "Ptr")
GetDesktopCountProc := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "GetDesktopCount", "Ptr")
MoveWindowToDesktopNumberProc := DllCall("GetProcAddress", "Ptr", hVDA, "AStr", "MoveWindowToDesktopNumber", "Ptr")

; ============================================================
; HOTKEYS
; ============================================================
!F1::StartDevMode()
!F2::StopDevMode()
!F3::ShowHelp()

; Не завершать скрипт
return

; ============================================================
; START DEVMODE
; ============================================================
StartDevMode() {
    global

    ; Определяем активный профиль
    if (ACTIVE_PROFILE = 1) {
        profileName := P1_NAME
        profileApps := P1_APPS
        desktopsNeeded := P1_DESKTOPS
    } else if (ACTIVE_PROFILE = 2) {
        profileName := P2_NAME
        profileApps := P2_APPS
        desktopsNeeded := P2_DESKTOPS
    } else {
        profileName := P3_NAME
        profileApps := P3_APPS
        desktopsNeeded := P3_DESKTOPS
    }

    ToolTip, DevMode: Starting "%profileName%"...

    ; 1. Убить процессы
    for i, procName in KILL_PROCESSES {
        KillProcess(procName)
    }
    Sleep, 500

    ; 2. Создать виртуальные столы если нужно
    EnsureDesktopCount(desktopsNeeded)
    Sleep, 300

    ; 3. Перейти на Desktop 0
    VD_GoToDesktop(0)
    Sleep, 200

    ; 4. Запустить и расставить приложения
    totalApps := profileApps.Length()
    for i, app in profileApps {
        ToolTip, DevMode: Launching %i%/%totalApps%...

        ; Проверяем, не запущено ли уже
        procFileName := GetProcessName(app.exe)
        Process, Exist, %procFileName%
        alreadyRunning := ErrorLevel

        hwnd := 0

        if (alreadyRunning) {
            ; Уже запущено — находим окно
            WinGet, hwnd, ID, % app.winClass
        } else {
            ; Запускаем
            Run, % app.exe " " app.args, , , pid
            ; Ждём появления окна
            timeoutSec := app.delay / 1000
            WinWait, % app.winClass, , %timeoutSec%
            if (!ErrorLevel) {
                WinGet, hwnd, ID, % app.winClass
            }
        }

        if (hwnd) {
            ; Сначала позиционируем (пока окно на текущем столе)
            PositionWindow(hwnd, app.position)
            Sleep, 100

            ; Затем перемещаем на нужный стол
            if (app.desktop > 0) {
                VD_MoveWindowToDesktop(hwnd, app.desktop)
                Sleep, 100
            }
        }

        Sleep, 300
    }

    ; 5. Вернуться на Desktop 0
    VD_GoToDesktop(0)
    Sleep, 200

    ToolTip, DevMode "%profileName%" started!
    SetTimer, ClearToolTip, -3000
}

; ============================================================
; STOP DEVMODE
; ============================================================
StopDevMode() {
    global

    ToolTip, DevMode: Stopping...

    ; Определяем активный профиль
    if (ACTIVE_PROFILE = 1) {
        profileApps := P1_APPS
    } else if (ACTIVE_PROFILE = 2) {
        profileApps := P2_APPS
    } else {
        profileApps := P3_APPS
    }

    ; 1. Закрыть приложения профиля
    for i, app in profileApps {
        procFileName := GetProcessName(app.exe)
        KillProcess(procFileName)
    }

    ; 2. Убить процессы на dev-портах
    psScript := A_ScriptDir . "\kill-dev-ports.ps1"
    if (FileExist(psScript)) {
        RunWait, powershell.exe -ExecutionPolicy Bypass -File "%psScript%", , Hide
    }

    Sleep, 500

    ; 3. Вернуться на Desktop 0
    VD_GoToDesktop(0)

    ToolTip, DevMode stopped!
    SetTimer, ClearToolTip, -3000
}

; ============================================================
; HELP
; ============================================================
ShowHelp() {
    global ACTIVE_PROFILE, P1_NAME, P2_NAME, P3_NAME
    MsgBox, 64, DevMode PC — Hotkeys,
    (
DevMode PC Hotkeys:

  Alt+F1  — Start devMode (active profile)
  Alt+F2  — Stop devMode (close all + kill ports)
  Alt+F3  — Show this help

Profiles:
  1: %P1_NAME%
  2: %P2_NAME%
  3: %P3_NAME%

Active profile: %ACTIVE_PROFILE%
Edit ACTIVE_PROFILE at the top of the script to switch.
    )
}

; ============================================================
; VIRTUAL DESKTOP HELPERS
; ============================================================
VD_GetCurrentDesktop() {
    global GetCurrentDesktopNumberProc
    return DllCall(GetCurrentDesktopNumberProc, "Int")
}

VD_GetDesktopCount() {
    global GetDesktopCountProc
    return DllCall(GetDesktopCountProc, "Int")
}

VD_GoToDesktop(num) {
    global GoToDesktopNumberProc
    DllCall(GoToDesktopNumberProc, "Int", num, "Int")
}

VD_MoveWindowToDesktop(hwnd, desktopNum) {
    global MoveWindowToDesktopNumberProc
    DllCall(MoveWindowToDesktopNumberProc, "Ptr", hwnd, "Int", desktopNum, "Int")
}

EnsureDesktopCount(needed) {
    currentCount := VD_GetDesktopCount()
    originalDesktop := VD_GetCurrentDesktop()

    while (currentCount < needed) {
        Send #^d
        Sleep, 300
        currentCount := VD_GetDesktopCount()
    }

    ; Вернуться на исходный стол если переключились
    if (VD_GetCurrentDesktop() != originalDesktop) {
        VD_GoToDesktop(originalDesktop)
        Sleep, 200
    }
}

; ============================================================
; WINDOW POSITIONING HELPERS
; ============================================================
PositionWindow(hwnd, position) {
    global MON1_X, MON1_Y, MON1_W, MON1_H
    global MON2_X, MON2_Y, MON2_W, MON2_H
    global TASKBAR_H

    ; Снять максимизацию перед перемещением
    WinRestore, ahk_id %hwnd%
    Sleep, 50

    if (position = "LEFT_PRIMARY") {
        x := MON1_X
        y := MON1_Y
        w := MON1_W // 2
        h := MON1_H - TASKBAR_H
    } else if (position = "RIGHT_PRIMARY") {
        x := MON1_X + (MON1_W // 2)
        y := MON1_Y
        w := MON1_W // 2
        h := MON1_H - TASKBAR_H
    } else if (position = "FULL_PRIMARY") {
        WinMove, ahk_id %hwnd%, , MON1_X, MON1_Y, MON1_W, MON1_H
        WinMaximize, ahk_id %hwnd%
        return
    } else if (position = "LEFT_SECONDARY") {
        x := MON2_X
        y := MON2_Y
        w := MON2_W // 2
        h := MON2_H - TASKBAR_H
    } else if (position = "RIGHT_SECONDARY") {
        x := MON2_X + (MON2_W // 2)
        y := MON2_Y
        w := MON2_W // 2
        h := MON2_H - TASKBAR_H
    } else if (position = "FULL_SECONDARY") {
        WinMove, ahk_id %hwnd%, , MON2_X, MON2_Y, MON2_W, MON2_H
        WinMaximize, ahk_id %hwnd%
        return
    } else if (InStr(position, "CUSTOM,")) {
        ; Формат: "CUSTOM,x,y,w,h"
        parts := StrSplit(position, ",")
        x := parts[2]
        y := parts[3]
        w := parts[4]
        h := parts[5]
    } else {
        return
    }

    WinMove, ahk_id %hwnd%, , x, y, w, h
}

; ============================================================
; PROCESS HELPERS
; ============================================================
KillProcess(processName) {
    Process, Exist, %processName%
    if (ErrorLevel) {
        Process, Close, %processName%
        Process, WaitClose, %processName%, 2
        if (ErrorLevel) {
            RunWait, taskkill /F /IM "%processName%", , Hide
        }
    }
}

GetProcessName(exePath) {
    SplitPath, exePath, fileName
    return fileName
}

; ============================================================
; UTILITY
; ============================================================
ClearToolTip:
    ToolTip
    return

; ============================================================
; TRAY MENU
; ============================================================
Menu, Tray, Tip, DevMode PC
Menu, Tray, NoStandard
Menu, Tray, Add, Start DevMode (Alt+F1), TrayStart
Menu, Tray, Add, Stop DevMode (Alt+F2), TrayStop
Menu, Tray, Add,
Menu, Tray, Add, Help (Alt+F3), TrayHelp
Menu, Tray, Add, Reload Script, TrayReload
Menu, Tray, Add,
Menu, Tray, Add, Exit, TrayExit
return

TrayStart:
    StartDevMode()
    return
TrayStop:
    StopDevMode()
    return
TrayHelp:
    ShowHelp()
    return
TrayReload:
    Reload
    return
TrayExit:
    ExitApp
    return
