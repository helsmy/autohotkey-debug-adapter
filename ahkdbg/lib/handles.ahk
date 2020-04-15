; Record handle

class Handles
{
    __New(startHandle := "")
	{
        this.START_HANDLE := 1000
        this._handleMap := {}
        this._nextHandle := startHandle >= 0 ? startHandle : this.START_HANDLE
    }

    Reset()
	{
        this._nextHandle := this.START_HANDLE
        this._handleMap := {}
    }

	create(value)
	{
        handle := this._nextHandle++
        this._handleMap[handle] := value
        ; Fuck weakly typed!
        return handle+0
    }

	get(handle, dflt := "")
	{
        return this._handleMap.HasKey(handle) ? this._handleMap[handle] : dflt

    }
}