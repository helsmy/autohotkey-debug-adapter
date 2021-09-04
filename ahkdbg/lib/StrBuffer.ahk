/**
    Modified From AHKhttp, GPLv2
*/

class StrBuffer
{
    __New(len) {
        this.SetCapacity("buffer", len)
        this.length := 0
    }

    FromString(str, encoding := "UTF-8") {
        length := Buffer.GetStrSize(str, encoding)
        buffer := new Buffer(length)
        buffer.WriteStr(str)
        return buffer
    }

    GetStrSize(str, encoding := "UTF-8") {
        encodingSize := ((encoding="utf-16" || encoding="cp1200") ? 2 : 1)
        ; length of string, minus null char
        return StrPut(str, encoding) * encodingSize - encodingSize
    }

    WriteStr(str, encoding := "UTF-8") {
        length := this.GetStrSize(str, encoding)
        VarSetCapacity(text, length)
        StrPut(str, &text, encoding)

        this.Write(&text, length)
        return length
    }

    ; data is a pointer to the data
    Write(data, length) {
        p := this.GetPointer()
        DllCall("RtlMoveMemory", "uint", p + this.length, "uint", data, "uint", length)
        this.length += length
    }

    Append(ByRef buffer) {
        destP := this.GetPointer()
        sourceP := buffer.GetPointer()

        DllCall("RtlMoveMemory", "uint", destP + this.length, "uint", sourceP, "uint", buffer.length)
        this.length += buffer.length
    }

    LShift(len) {
        headP := this.GetPointer()
        ; Left Shift memory
        DllCall("RtlMoveMemory", "uint", headP, "uint", headP+len, "uint", this.length-len)
        ; set rest of memory to 0
        DllCall("RtlZeroMemory", "Uint", headP+(this.length-len), "Uint", len-1)
        this.length -= len
    }

    GetPointer() {
        return this.GetAddress("buffer")
    }

    Done() {
        this.SetCapacity("buffer", this.length)
    }

    GetLine(encoding := "UTF-8") {
        pos := this.FindStrA("`r`n")
        return (pos != "") ? StrGet(this.GetPointer(), pos+2, encoding) : ""
    }

    GetStr(len, encoding := "UTF-8") {
        len := Min(len, this.length)
        return StrGet(this.GetPointer(), len, encoding)
    }

    FindStrA(s) {
        ptr := DllCall("Shlwapi\StrStrIA", "Ptr", this.GetPointer(), "Str", s, "Ptr")
        return ptr ? ptr - this.GetPointer() : ""
    }
} 
