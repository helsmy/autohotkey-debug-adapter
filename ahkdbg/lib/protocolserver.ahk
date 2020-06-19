#Include <jsonlib>
#Include <fsarr>
#Include <stdio>
#Include <logger>

class ProtocolServer
{
	__New(inStream, outStream)
	{
		this.inStream := inStream
		this.RH := new RequestHandler(outStream)
		this.keepRun := true
	}

	SetApp(application)
	{
		this.application := application
	}

	ServeForever()
	{
		HOR := ObjBindMethod(this, "HandleOneRequest")
		While (this.keepRun)
		{
			r := this.inStream.Read()
			; Send request to EventDispatcher
			; hacking way only fit to stdio
			while (r)
			{
				header := StrSplit(r, "`r`n`r`n",,2)
				r := header[2]
				header := header[1]
				; What a difficult thing to make sure converting is right in v1 OTZ
				req_l := Trim(SubStr(header, 17), " `t`r`n") & -1
				cap := StrPut(r, "utf-8")
				VarSetCapacity(buffer, cap)
				StrPut(r, &buffer, cap, "utf-8")
				req := StrGet(&buffer, req_l+0, "utf-8")
				; Send request to EventDispatcher
				if (!!req)
					EventDispatcher.Put(HOR, req)
			}
		}
	}

	HandleOneRequest(request_data)
    {
        ; Construct environment dictionary using request data
        env := this.RH.ParseRequest(request_data)
		env.server := this
		if env.command != "waitConfiguration"
			logger("VSC -> DA Request: " request_data)
        result := this.application(env)

        ; Construct a response and send it back to the client
        this.RH.FinishResponse(result)
    }

	HandleEvent(event)
	{
		this.RH.Send(event)
	}
}

class EventDispatcher
{
	static eventQueue := []

	Put(handler, data, immediate := false)
	{
		if !immediate
			this.eventQueue.Push([handler, data])
		else
			this.eventQueue.InsertAt(2, [handler, data])
		; Using a single timer ensures that each handler finishes before
		; the next is called, and that each runs in its own thread.
		static DT := ObjBindMethod(EventDispatcher, "DispatchTimer")
		SetTimer, % DT, -1
	}

	DispatchTimer()
	{
		static DT := ObjBindMethod(EventDispatcher, "DispatchTimer")
		; Call exactly one handler per new thread.
		if next := this.eventQueue.RemoveAt(1)
			fn := next[1], %fn%(next[2])
		; If the queue is not empty, reset the timer.
		if this.eventQueue.Length()
			SetTimer, % DT, -1
	}

	On(event, handler)
	{
		if !this.handleMap
			this.handleMap := object(event, handler)
		else
			this.handleMap[event] := handler
	}

	EmitImmediately(event, data)
	{
		if this.handleMap.HasKey(event)
			this.Put(this.handleMap[event], data, true)
	}
}

class RequestHandler
{
	__New(outStream)
	{
		this.outStream := outStream
		this.seq := 1+0
	}

    ParseRequest(request_data)
    {
        return JSON.ToObj(request_data)
    }

    FinishResponse(result)
    {
		; loop in result one item creat one response
		; need finish
        try
        {
            for _, response in result
				this.Send(response)
        }
        catch err
        {
            FileAppend, % "Error: " err.message " " err.what "`n", **
        }
        ; finally

    }

	Send(response)
	{
		response["seq"] := this.seq
		; responseStr := JSON.FromObj(response)
		responseStr := fsarr().print(response)
		responseStr := StrReplace(responseStr, """true""" , "true")
		responseStr := StrReplace(responseStr, """false""" , "false")
		responseStr := StrReplace(responseStr, "`n" , "\n")
		responseStr := StrReplace(responseStr, "`t" , "\t")
		responseStr := StrReplace(responseStr, "`r" , "\r")
		if response.type == "event"
			logger("DA -> VSC event: " responseStr)
		else
			logger("DA -> VSC Response: " responseStr)
		responseStr := "Content-Length: " . (StrPut(responseStr, "utf-8")-1) . "`r`n`r`n" . responseStr

		this.outStream.Write(responseStr)
		this.seq++
	}
}

StrLenBit(string, ByRef var, encoding)
{
    ; 确定容量.
    VarSetCapacity( var, StrPut(string, encoding)
        ; StrPut 返回字符数, 但 VarSetCapacity 需要字节数.
        * ((encoding="utf-16"||encoding="cp1200") ? 2 : 1) )
    ; 复制或转换字符串.
    return StrPut(string, &var, encoding)
}

MakeServer(server_address, application)
{
    server := new ProtocolServer(server_address*)
    server.SetApp(application)
    return server
}
