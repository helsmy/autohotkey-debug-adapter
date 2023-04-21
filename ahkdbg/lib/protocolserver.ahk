#Include <jsonlib>
#Include <fsarr>
#Include <stdio>
#Include <logger>
#Include <StrBuffer>

class ProtocolServer
{
	__New(inStream, outStream)
	{
		this.inStream := inStream
		this.RH := new RequestHandler(outStream)
		this.keepRun := true
		this.buffer := new StrBuffer(512)
	}

	SetApp(application)
	{
		this.application := application
	}

	ServeForever()
	{
		; this.hStdin := DllCall("GetStdHandle","Uint", -10)
		; logger("Stdin Handle: " this.hStdin)
		; this.waitCallback := RegisterCallback("OnStdin")
		; this.hWait := RegisterWaitForSingleObject(this.hStdin, this.waitCallback, 0)
		; logger("Wait Object Handle: " this.hWait)
		HOR := ObjBindMethod(this, "HandleOneRequest")
		While (this.keepRun)
		{
			r := this.inStream.Read()
			; Send request to EventDispatcher
			; hacking way only fit to stdio
			if (r != "") 
				this.buffer.WriteStr(r)
			if (this.buffer.length > 0)
			{
				line := this.buffer.GetLine()
				header := Trim(line, "`r`n `t")
				Logger("header: " header)
				if (InStr(header, "Content-Length")) 
				{
					req_l := Trim(SubStr(header, 17), " `t`r`n") & -1
					Logger("request length:" req_l)
					; remove header line and \r\n spliter, 
					; StrPut会返回带终止\0的长度，所以再额外加1即可
					this.buffer.LShift(StrPut(line, "UTF-8")+1)
					req := this.buffer.GetStr(req_l)
					this.buffer.LShift(req_l)
					Logger("Got request:" req)
					EventDispatcher.Put(HOR, req)
				}
				else
					; skip unknow request
					this.buffer.LShift(StrPut(line, "UTF-8") - 1)
			}
			; else
			; 	Sleep 20
			; while (r)
			; {
			; 	; Logger("Stdin Full: " r)
			; 	header := StrSplit(r, "`r`n`r`n",,2)
			; 	; Logger("Header: " header[1])
			; 	r := header[2]
			; 	header := header[1]
			; 	; What a difficult thing to make sure converting is right in v1 OTZ
			; 	req_l := Trim(SubStr(header, 17), " `t`r`n") & -1
			; 	cap := StrPut(r, "utf-8")
			; 	VarSetCapacity(buffer, cap)
			; 	StrPut(r, &buffer, cap, "utf-8")
			; 	req := StrGet(&buffer, req_l+0, "utf-8")
			; 	; Send request to EventDispatcher
			; 	; FIXME: UTF-8 block dispatcher
			; 	if (!!req)
			; 		EventDispatcher.Put(HOR, req)
			; }
			; sleep 20
		}
		; DllCall("UnregisterWaitEx", "Uint", this.hWait, "Uint", -1)
		; this.hWait := 0

	}

	STDINCallBack(header)
	{
		HOR := ObjBindMethod(this, "HandleOneRequest")
		this.buffer.WriteStr(header)
		header := this.buffer.GetLine()
		if (InStr(header, "Content-Length")) 
		{
			req_l := Trim(SubStr(header, 17), " `t`r`n") & -1
			this.inStream.RawRead(r, req_l+2)
			this.buffer.Write(&r)
			; remove header line and \r\n spliter, 
			; StrPut会返回带终止\0的长度，所以再额外加1即可
			this.buffer.LShift(StrPut(line, "UTF-8")+1)
			req := this.buffer.GetStr(req_l)
			this.buffer.LShift(req_l)
			EventDispatcher.Put(HOR, req)
		}
		else
			; skip unknow request
			this.buffer.LShift(StrPut(line, "UTF-8") - 1)
		
	}

	HandleOneRequest(request_data)
    {
		Logger("Hanlder:" request_data)
        ; Construct environment dictionary using request data
        env := this.RH.ParseRequest(request_data)
		env.server := this
		if env.command != "waitConfiguration"
			logger("VSC -> DA Request: " request_data)
		Logger("send to reponser: " env.command)
        result := this.application(env)

        ; Construct a response and send it back to the client
        this.RH.FinishResponse(result)
    }

	; Resume a respone of a request
	; For async wait of configuration done
	ResumeRequest(env_data) 
	{
		result := this.application(env_data)
		if (!!result)
			this.RH.FinishResponse(result)
	}

	OnRecv()
	{
		ToolTip, Console Input Read!
		DllCall("UnregisterWaitEx", "Uint", this.hWait, "Uint", -1)
		this.hWait := 0
		HOR := ObjBindMethod(this, "HandleOneRequest")
		r := this.inStream.Read()
		; this.hWait := RegisterWaitForSingleObject(this.hStdin, this.waitCallback, 0)
		logger(r)
		; Send request to EventDispatcher
		; hacking way only fit to stdio
		while (r)
		{
			header := StrSplit(r, "`r`n`r`n",,2)
			r := header[2]
			header := header[1]
			; What a difficult thing to make sure converting is right in v1 OTZ
			req_l := Trim(SubStr(header, 17), " `t`r`n") & -1
			StrPut(r, &buffer, req_l, "utf-8")
			req := StrGet(&buffer, req_l+0, "utf-8")
			; Send request to EventDispatcher
			; FIXME: UTF-8 block dispatcher
			if (!!req)
				EventDispatcher.Put(HOR, req)
		}
	}

	HandleEvent(event)
	{
		this.RH.Send(event)
	}

	__Delete()
	{
		this.buffer.length := 0
		this.buffer.Done()
	}
}

class EventDispatcher
{
	static eventQueue := []
	static immediateQueue := []

	Put(handler, data, immediate := false)
	{
		
		if !immediate
			this.eventQueue.Push([handler, data])
		else
			this.immediateQueue.Push([handler, data])
		Logger("Put response " this.eventQueue.Length() " for:" data)
		; Using a single timer ensures that each handler finishes before
		; the next is called, and that each runs in its own thread.
		DT := ObjBindMethod(EventDispatcher, "DispatchTimer")
		SetTimer, % DT, -1
	}

	DispatchTimer()
	{
		DT := ObjBindMethod(EventDispatcher, "DispatchTimer")
		; Clear immediateQueue array before fire handler of eventQueue
		if (next := this.immediateQueue.RemoveAt(1))
			Logger("fire response for:" next[2]),fn := next[1], %fn%(next[2])
		; Call exactly one handler per new thread.
		else if next := this.eventQueue.RemoveAt(1) {
			Logger("fire response for:" next[2])
			fn := next[1]
			Logger("handler name: " fn.MinParams)
			fn.Call(next[2])
		}
		; If the queue is not empty, reset the timer.
		if (this.eventQueue.Length() || this.immediateQueue.Length())
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
		responseStr := this.ReplaceControlChr(responseStr, (response["type"] != "event"))
		if response.type == "event"
			logger("DA -> VSC event: " responseStr)
		else
			logger("DA -> VSC Response: " responseStr)
		responseStr := "Content-Length: " . (StrPut(responseStr, "utf-8")-1) . "`r`n`r`n" . responseStr

		this.outStream.Write(responseStr)
		this.seq++
	}

	ReplaceControlChr(s, isEascapeCR := false)
	{
		if !isEascapeCR
			s := StrReplace(s, "`n" , "\n")
			,s := StrReplace(s, "`t" , "\t")
			,s := StrReplace(s, "`r" , "\r")
		loop
			if (RegExMatch(s, "[\cA-\cZ]", char))
				s := StrReplace(s, char, "``" Chr(Ord(char)+0x40))
			else
				break
		
		return s
	}
}

MakeServer(server_address, application)
{
	server := new ProtocolServer(server_address*)
	server_address[1].SetProcesser(ObjBindMethod(server, "STDCallBack"))
	EventDispatcher.On("recv", ObjBindMethod(server, "OnRecv"))
    server.SetApp(application)
    return server
}

RegisterWaitForSingleObject(waitObject, waitCallBack, state, timeout := -1, execOption := true)
{
    VarSetCapacity(hWait, 16, 0)
    ; WT_EXECUTEONLYONCE: 0x00000008, WT_EXECUTEDEFAULT: 0
    execOption := executeOnlyOnce ? 0x00000008 : 0x00000000      
    if (DllCall("RegisterWaitForSingleObject", "UInt", &hWait
                    , "Uint", waitObject
                    , "Uint", waitCallback
                    , "Uint", state
                    , "Uint", timeout
                    , "Uint", execOption) == 0)
    {
        throw Exception("RegisterWaitForSingleObject Error" , -1, "Error Code: " DllCall("GetLastError"))
    }
	; logger("Function hWait: " hWait)
    return NumGet(hWait)+0
}

OnStdin(lpParameter, TimerOrWaitFired) 
{
	CallBackStd()
}

CallBackStd()
{
	; stdin := FileOpen("*", "r")
	EventDispatcher.EmitImmediately("recv", "")
	
}
