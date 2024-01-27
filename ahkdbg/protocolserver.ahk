#Include <JSON>
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
		this.buffer := new StrBuffer(512)
		this.reqQueue := []
	}

	SetApp(application)
	{
		this.application := application
	}

	ServeForever()
	{
		hStdin := DllCall("GetStdHandle","Uint", -10)
		; Let cJson return boolen in Json way
		JSON.BoolsAsInts := true
		; while (!A_DebuggerName) {
		; 	sleep, 20
		; }
		; HOR := ObjBindMethod(this, "HandleOneRequest")
		While (this.keepRun)
		{
			bytesAvail := 0
			bytesRead := 0
			status1 := DllCall("PeekNamedPipe", "Ptr", hStdin, "Int", 0, "Int", 0, "Int", 0, "Int*", bytesAvail, "Int", 0, "Int")
			; lastError := DllCall("GetLastError", "int")
			; if (status1 != 0)
			; 	throw Exception("System Error Code:" DllCall("GetLastError", "int"))
			while (bytesAvail > 0) 
			{
				header := this.inStream.ReadLine()
				reqLen := Trim(SubStr(header, 17), " `t`r`n") & -1
				this.inStream.ReadLine()
				req := this.inStream.RawRead(reqLen)
				this.reqQueue.Push(req)
				; check if there are next request
				bytesAvail -= StrLen(header)+2+reqLen
				continue
			}

			while (request_data := this.reqQueue.RemoveAt(1)) 
			{
				this.HandleOneRequest(request_data)
				; continue
			}
			; Avoid smashing cpu
			sleep 10
		}
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
        return JSON.Load(request_data)
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
		responseStr := JSON.Dump(response)
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
