class Logger
{
    __New() {
        this._pendingQ := []
        this.initialized := false
        this.logLevel := LogLevel.Error
    }

    Init() {
        this.initialized := true
    }

    info(str) {
        ;    Edit_Append(hEdit, str "`n")
        
        logOutputEvent := CreateOutputEvent("console", str)
        logOutputEvent["body"]["data"] := "LogEvent"

        if (!this.initialized) {
            this._pendingQ.Push(logOutputEvent)
            return
        }
        else if (!!this._pendingQ) {
            if (this.logLevel > LogLevel.info) {
                this._pendingQ := ""
                return
            }
            for _, e in this._pendingQ 
                EventDispatcher.EmitImmediately("send", e)
            this._pendingQ := ""
        } 

        if (this.logLevel > LogLevel.info) 
            return
        EventDispatcher.EmitImmediately("send", logOutputEvent)
            ; EventDispatcher.EmitImmediately("sendEvent", CreateOutputEvent("stdout", str "`n"))
    }
}

class LogLevel {
    static info := 1
    static Error := 4
}
;Edit_Append(hEdit, Txt) { ; Modified version by SKAN
;Local        ; Original by TheGood on 09-Apr-2010 @ autohotkey.com/board/topic/52441-/?p=328342
;  L := DllCall("SendMessage", "Ptr",hEdit, "UInt",0x0E, "Ptr",0 , "Ptr",0)   ; WM_GETTEXTLENGTH
;       DllCall("SendMessage", "Ptr",hEdit, "UInt",0xB1, "Ptr",L , "Ptr",L)   ; EM_SETSEL
;       DllCall("SendMessage", "Ptr",hEdit, "UInt",0xC2, "Ptr",0 , "Str",Txt) ; EM_REPLACESEL
;}