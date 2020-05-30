Logger(str)
{
    global isdebug
    if !isdebug
        return
    
    if InStr(str, "initialize")
        FileAppend, % "`n`n" str "`n", % A_ScriptDir "\ahkdbg.log"
    FileAppend, % str "`n", % A_ScriptDir "\ahkdbg.log"
    ; str := StrReplace(str, """", "\""")
    ; EventDispatcher.EmitImmediately("sendEvent", CreateOutputEvent("stdout", str "`n"))
}