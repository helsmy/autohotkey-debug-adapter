Logger(str)
{
    global isdebug
    if !isdebug
        return
    
    Edit_Append(hEdit, str "`n")

    ; if InStr(str, "initialize")
    ;     FileAppend, % "`n`n" str "`n", % A_ScriptDir "\ahkdbg.log"
    ; FileAppend, % str "`n", % A_ScriptDir "\ahkdbg.log"
    ; str := StrReplace(str, """", "\""")
    ; EventDispatcher.EmitImmediately("sendEvent", CreateOutputEvent("stdout", str "`n"))
}

Edit_Append(hEdit, Txt) { ; Modified version by SKAN
Local        ; Original by TheGood on 09-Apr-2010 @ autohotkey.com/board/topic/52441-/?p=328342
  L := DllCall("SendMessage", "Ptr",hEdit, "UInt",0x0E, "Ptr",0 , "Ptr",0)   ; WM_GETTEXTLENGTH
       DllCall("SendMessage", "Ptr",hEdit, "UInt",0xB1, "Ptr",L , "Ptr",L)   ; EM_SETSEL
       DllCall("SendMessage", "Ptr",hEdit, "UInt",0xC2, "Ptr",0 , "Str",Txt) ; EM_REPLACESEL
}