#Include %A_ScriptDir%
#Include <jsonlib>
#Include <stdio>
#Include <handles>
#Include <event>
#Include <protocolserver>
#Include <application>
#Include ./AHKRuntime.ahk

class DebugSession extends Application
{
    static THREAD_ID := 1

    __New()
    {
        this._configurationDone := false
        this._timeout := false
		this.isStart := false
        this._variableHandles := new Handles()
        this._runtime := new AHKRunTime()
    }

    CheckTimeOut()
    {
        this._timeout := true
        ; MsgBox, timeout!
    }

    initializeRequest(response, env)
    {
        ; body
        response["body"] := {}
        response.body["supportsConfigurationDoneRequest"] := "true"
        ; response.body["supportsEvaluateForHovers"] := "true"
        ; response.body["supportsDataBreakpoints"] := "true"
        ; response.body["supportsBreakpointLocationsRequest"] := "true"
        response.body["supportsClipboardContext"] := "true"

        InitializedEvent := {"type": "event", "event": "initialized"}
		this._runtime.Init(env.arguments)
        return [response, InitializedEvent]
    }

    configurationDoneRequest(response, env)
    {
        ; Sleep, 2000 ; test timeout
        this._configurationDone := true
        ; MsgBox, _configurationDone!

        return [response]
    }

    ; async exec
    launchRequest(response, env)
    {
		; start ahk debug here
		if !this.isStart
		{
            this._runtime.dbgCaptureStreams := (env.arguments.captureStreams == "true") ? true : false
			this._runtime.Start(env.arguments.program)
			this.isStart := true
		}

        ; wait until configuration has finished (and configurationDoneRequest has been called)
        ; Async wait by send WaitConfiguration event to event queue
        if (!this._configurationDone) ; and !this._timeout
        {
            CTO := ObjBindMethod(this, "CheckTimeOut")
            SetTimer, % CTO, -1000
            Sleep, 25
            server := env.server
            seq := env.seq

            HOR := ObjBindMethod(server, "HandleOneRequest")

            waitConfigurationRequest := {"command": "waitConfiguration", "seq": seq}
            waitConfigurationRequest["arguments"] := env.arguments
            waitConfigurationRequest := fsarr().print(waitConfigurationRequest)

            waitConfigurationRequest := "Content-Length: " StrLen(waitConfigurationRequest) "`r`n`r`n" . waitConfigurationRequest
            EventDispatcher.Put(HOR, waitConfigurationRequest)
            ; empty list won't fire send method
            return []
        }

        response["command"] := "launch"
        stopOnEntry := (env.arguments.stopOnEntry == "true") ? true : false
        this._runtime.StartRun(stopOnEntry)
        ; Send a 'Stop on Entry' Stopped event, to make vs code stop on entry
        ; stoppedEvent := CreateStoppedEvent("entry", DebugSession.THREAD_ID)

        return [response]
    }

    waitConfigurationRequest(response, env)
    {
        ; Mock Request to wait ConfigurationDoneRequest
        return this.launchRequest(response, env)
    }

    setBreakPointsRequest(response, env)
    {
        path := env.arguments.source.path
        clientLines := env.arguments.breakpoints

        ; clear all breakpoints for this file
        this._runtime.clearBreakpoints(path)

        ; set and verify breakpoint locations
        actualBreakpoints := []
        for _, line  in clientLines
        {
			; Why no Exception about wrong parameter?
            bkp := this._runtime.SetBreakpoint(path, line.line)
            ; Fuck Weakly Typed!
            actualBreakpoints.Push(CreateBreakpoint(bkp.verified, bkp.id, bkp.line+0))
            ;verifyEvent.Push(CreateBreakpointEvent("changed", CreateBreakpoint("true", bkp.id, bkp.line)))
        }
        this._runtime.VerifyBreakpoints()
        ; body
        response["body"] := {}
        response.body["breakpoints"] := actualBreakpoints
        return [response]
    }

    setDataBreakpointsRequest(response, env)
    {
        ; set and verify breakpoint locations
        ; temp return all breakpoint of request
        if (env.arguments.breakpoints.Length() > 0)
            actualBreakpoints := env.arguments.breakpoints
        else
            actualBreakpoints := []

        ; body
        response["body"] := {}
        response.body["breakpoints"] := actualBreakpoints

        return [response]
    }

    breakpointLocationsRequest(response, env)
    {
        ; may xdbg doesn't support breakpointLocations
        response["body"] := {}
        response.body["breakpoints"] := {"line": env.arguments.line+0, "column": 1+0}

        return [response]
    }

    threadsRequest(response, env)
    {
        ; runtime supports no threads so just return a default thread.
        response["body"] := {"threads": [{"id": DebugSession.THREAD_ID, "name": "thread 1"}]}

        return [response]
    }

    stackTraceRequest(response, env)
    {
        startFrame := env.arguments.startFrame >= 0 ? env.arguments.startFrame : 0
        maxLevels := env.arguments.levels >= 0 ? env.arguments.startFrame : 1000
        endFrame := startFrame + maxLevels

        ; source := {"name": this._runtime.GetBaseFile(), "path":this._runtime.GetPath(), "sourceReference": 0+0, "data": "mockdata"}
		stack := this._runtime.GetStack()
		stackFrames := []
		Loop % stack.where.Length()
		{
			source := {"name": this.GetBaseFile(stack.file[A_Index]), "path":StrReplace(stack.file[A_Index], "\", "/"), "sourceReference": 0+0, "adapterData": "mockdata"}
			stackFrames.Push({"id": stack.level[A_Index]+0, "name": stack.where[A_Index], "line": stack.line[A_Index]+0, "source": source, "column": 1+0}) ;
			; MsgBox, % fsarr().print(source)
		}
        ; response a constant stack frame for now
        response["body"] := {}
        response.body["stackFrames"] := stackFrames
        response.body["totalFrames"] := stackFrames.Length()

        return [response]
    }

    scopesRequest(response, env)
    {
        frameId := env.arguments.frameId
        response["body"] := {}
        response.body["scopes"] := [{"name": "Local", "variablesReference": this._variableHandles.create(["Local", frameId]), "expensive": "false"}
                                  , {"name": "Global", "variablesReference": this._variableHandles.create(["Global", "None"]), "expensive": "true"}]
        return [response]
    }

    ; TODO: May long running, need async exec here
    ; FIXME: UTF char cause wrong
    variablesRequest(response, env)
    {
        ; just return some constant value, for now
        id := this._variableHandles.get(env.arguments.variablesReference)
        variables := []
        ; Return variable list
        if (id)
        {
            variablesRaw := this._runtime.CheckVariables(id[1], id[2])
            Loop % variablesRaw.name.Length()
            {
				if (variablesRaw.name[A_Index] = "true" or variablesRaw.name[A_Index] = "false")
					variablesRaw.name[A_Index] .= " "
				; FIXME: "" return value is undefined,
				; FIXME: problem in name is 'true' or 'false'
                variables.Push({"name": variablesRaw.name[A_Index]
                               ,"type": variablesRaw.type[A_Index]
                               ,"value": variablesRaw.type[A_Index] == "undefined" ? "undefined" : variablesRaw.value[A_Index]
                               ,"variablesReference"
							   : variablesRaw.type[A_Index] == "object" 
                               ? this._variableHandles.create([variablesRaw.name[A_Index], id[2]])+0 : 0})
            }
        }
		; MsgBox, % fsarr().print(variables)

        response["body"] := {"variables": variables}

        return [response]
    }

    continueRequest(response, env)
    {
        this._runtime.Continue()
        return [response]
    }

    nextRequest(response, env)
    {
		this._variableHandles.Reset()
        this._runtime.Next()
        return [response, CreateStoppedEvent("step", DebugSession.THREAD_ID)]
    }

    stepInRequest(response, env)
    {
		this._variableHandles.Reset()
        this._runtime.StepIn()
        return [response, CreateStoppedEvent("step", DebugSession.THREAD_ID)]
    }

    stepOutRequest(response, env)
    {
		this._variableHandles.Reset()
        this._runtime.StepOut()
        return [response]
    }

	pauseRequest(response, env)
	{
		this._variableHandles.Reset()
		this._runtime.Pause()
		return [response, CreateStoppedEvent("pause", DebugSession.THREAD_ID)]
	}

    disconnectRequest(response, env)
    {
        this._runtime.DBGp_CloseDebugger()
		if Util_ProcessExist(this.Dbg_PID)
			Process, Close, % this.Dbg_PID
		this.isStart := false
        ; TODO: ExitApp here
        ; if ！env.arguments.restart
        ;     SetTimer, quit, -100    
        return [response]
    }

	errorResponse(response, env)
	{
        ; TODO: send error info here
		response.success := "false"
		return [response]
	}

	GetBaseFile(path)
	{
		SplitPath, % path, name
		return name
	}
}
