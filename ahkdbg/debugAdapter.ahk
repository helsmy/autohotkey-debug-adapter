#SingleInstance Force
#NoEnv
#NoTrayIcon
; SetBatchLines 20ms
ListLines Off
SetWorkingDir %A_ScriptDir%

#Include %A_ScriptDir%
#Include ./AHKDebug.ahk

FileEncoding, utf-8
isdebug := false
global hEdit := CreateGui()

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


CreateGui()
{
    global isdebug
    if (!isdebug) 
        return
    Gui, New, +AlwaysOnTop
    Gui, Margin, 15, 15
    Gui, Font, s9, Consolas
    Gui, Add, Text,, Output
    Gui, Add, Edit, y+3 -Wrap +HScroll R20 HwndhEdit1, % Format("{:81}", "")
    ControlGetPos,,,W,,,ahk_id %hEdit1%
    Gui, Add, Text,, Command Line
    Gui, Add, Edit, y+3 -Wrap HwndhEdit2 w%W%, Dir
    ; Gui, Add, Button, x+0 w0 h0 Default gRunCMD, <F2> RunCMD
    Gui, Add, StatusBar
    SB_SetParts(200,200), SB_SetText("`t<Esc> Cancel/Clear", 1),  SB_SetText("`t<Enter> RunCMD", 2)
    GuiControl,, Edit1
    Gui, Show,, RunCMD() - Realtime per line streaming demo 


    SB_SetText("", 3)
    GuiControlGet, Cmd,, %hEdit2%
    GuiControl, Disable, Button1
    ; ExitCode := RunCMD(A_Comspec . " /c " . Cmd)
    ; SB_SetText("`tExitCode : " ErrorLevel, 3)
    GuiControl, Enable, Button1
    Edit_Append(hEdit2,"")
    GuiControl, Focus,Edit2

    return hEdit1
}