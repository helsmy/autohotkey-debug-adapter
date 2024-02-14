;@Ahk2Exe-SetProductName AHK Debug Adapter
;@Ahk2Exe-ConsoleApp

; Make it less easier to detect as Autohotkey
;@Ahk2Exe-Obey U_au, = "%A_IsUnicode%" ? 2 : 1    ; Script ANSI or Unicode?
;@Ahk2Exe-PostExec "BinMod.exe" "%A_WorkFileName%"
;@Ahk2Exe-Cont  "%U_au%2.>AUTOHOTKEY SCRIPT<. RANDOM"
;@Ahk2Exe-Cont  "%U_au%.AutoHotkeyGUI.RANDOM"
;@Ahk2Exe-UpdateManifest 0 ,.

#SingleInstance Force
#NoEnv
#NoTrayIcon
#Requires AutoHotkey v1.1.36+
SetBatchLines -1
ListLines Off
SetWorkingDir %A_ScriptDir%

#Include %A_ScriptDir%
#Include ./AHKDebug.ahk
#Include <JSON>

isdebug := false

descript  := "AutoHotkey Debug Adapter`nDebug Adapter for AutoHotKey implemented by AutoHotKey."
helpUsage := "For more infomation see: https://github.com/helsmy/autohotkey-debug-adaptor"
if (A_Args.Length() >= 1) {
    arg1 := A_Args.RemoveAt(1)
    FileAppend %arg1%, **
    if (arg1 == "--help" || arg1 == "-h") 
        FileAppend %descript%`n`n%helpUsage%`n`n, *
    if (arg1 != "")
        ExitApp 0
}
; global hEdit := CreateGui()

; Let cJson return boolen in Json way
JSON.BoolsAsInts := false
IOStream := new StdIO()
SERVER_ADDRESS := [IOStream, IOStream]
module := new DebugSession()
app := module.BuildApp()

DAd := MakeServer(SERVER_ADDRESS, app)
; Register send event handler
EventDispatcher.On("sendEvent", ObjBindMethod(DAd, "HandleEvent"))
OnError("GlobalErrorHandler")

DAd.ServeForever()

GlobalErrorHandler(exception)
{
    EventDispatcher.EmitImmediately("sendEvent", CreateOutputEvent("stdout", "Debug Adapter Error:" exception.Message "Sepecially: " exception.Extra))
    EventDispatcher.EmitImmediately("sendEvent", CreateTerminatedEvent())
}

; WaitDebugger() {
;     while (!A_DebuggerName) {
;         sleep, 20
;     }
; }


; CreateGui()
; {
;     global isdebug
;     if (!isdebug) 
;         return
;     Gui, New, +AlwaysOnTop
;     Gui, Margin, 15, 15
;     Gui, Font, s9, Consolas
;     Gui, Add, Text,, Output
;     Gui, Add, Edit, y+3 -Wrap +HScroll +Multi R20 HwndhEdit1, % Format("{:81}", "")
;     ControlGetPos,,,W,,,ahk_id %hEdit1%
;     Gui, Add, Text,, Command Line
;     Gui, Add, Edit, y+3 -Wrap HwndhEdit2 w%W%, Dir
;     ; Gui, Add, Button, x+0 w0 h0 Default gRunCMD, <F2> RunCMD
;     Gui, Add, StatusBar
;     SB_SetParts(200,200), SB_SetText("`t<Esc> Cancel/Clear", 1),  SB_SetText("`t<Enter> RunCMD", 2)
;     GuiControl,, Edit1
;     Gui, Show,, RunCMD() - Realtime per line streaming demo 


;     SB_SetText("", 3)
;     GuiControlGet, Cmd,, %hEdit2%
;     GuiControl, Disable, Button1
;     ; ExitCode := RunCMD(A_Comspec . " /c " . Cmd)
;     ; SB_SetText("`tExitCode : " ErrorLevel, 3)
;     GuiControl, Enable, Button1
;     Edit_Append(hEdit2,"")
;     GuiControl, Focus,Edit2

;     return hEdit1
; }