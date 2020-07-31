#SingleInstance Force
#NoEnv
#NoTrayIcon
; SetBatchLines 20ms
ListLines Off
SetWorkingDir %A_ScriptDir%

#Include %A_ScriptDir%
#Include ./AHKDebug.ahk

FileEncoding, utf-8
IOStream := new StdIO
isdebug := false

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
    EventDispatcher.EmitImmediately("sendEvent", CreateOutputEvent("stdout", "Debug Adapter Error:" exception.Message))
    EventDispatcher.EmitImmediately("sendEvent", CreateTerminatedEvent())
}
