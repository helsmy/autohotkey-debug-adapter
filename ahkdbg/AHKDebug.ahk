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
        response.body["supportsSetVariable"] := "true"
        response.body["supportsClipboardContext"] := "true"
        ; experimental features
        response.body["supportsHitConditionalBreakpoints"] := "true"
        ; response.body["supportsEvaluateForHovers"] := "true"
        ; response.body["supportsFunctionBreakpoints"] := "true"
        ; response.body["supportsBreakpointLocationsRequest"] := "true"

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
            this._runtime.AhkExecutable := FileExist(env.arguments.AhkExecutable) ? env.arguments.AhkExecutable : this._runtime.AhkExecutable
            this._runtime.dbgPort := env.arguments.port
            noDebug := (env.arguments.noDebug == "true") ? true : false
            try
                this._runtime.Start(env.arguments.program, noDebug)
            catch e
            {
                response["body"] := {"error": CreateMessage(-1,env.arguments.program " launch fail`n" e.Message "`nExtra:" e.Extra)}
                return this.errorResponse(response, env)
            }
            if noDebug
            {
                env.server.keepRun := false ; Stop server, not a good solution for running without debug
                this.isStart := false
                return [response]
            }
            else
                this.isStart := true
		}

        ; wait until configuration has finished (and configurationDoneRequest has been called)
        ; Async wait by send WaitConfiguration event to event queue
        if (!this._configurationDone and !this._timeout)
        {
            CTO := ObjBindMethod(this, "CheckTimeOut")
            SetTimer, % CTO, -1000
            ; Sleep, 25
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

    setBreakpointsRequest(response, env)
    {
        path := env.arguments.source.path
        l_bkinfo := env.arguments.breakpoints

        ; clear all breakpoints for this file
        ; this._runtime.clearBreakpoints(path)

        ; set and verify breakpoint locations
        actualBreakpoints := []
        bkcheckdict := {}
        for _, bkinfo  in l_bkinfo
        {
            try
            {
                ; Why no Exception about wrong parameter?
                bkp := this._runtime.SetBreakpoint(path, bkinfo)
                source := {"name": this.GetBaseFile(bkp.source), "path": bkp.source, "sourceReference": 0+0}
                ; Fuck Weakly Typed!
                actualBreakpoints.Push(CreateBreakpoint(bkp.verified, bkp.id, bkp.line+0, , source)) ;
            }
            catch err
                actualBreakpoints.Push(CreateBreakpoint("false",, bkinfo.line+0, 0, path, err.Extra))
            finally
                bkcheckdict[bkp.line] := ""
        }

        ; Remove unnecessary breakpoint
        this._runtime.DeleteBreakpoint(path, bkcheckdict)
        this._runtime.VerifyBreakpoints(path)
        ; body
        response["body"] := {}
        response.body["breakpoints"] := actualBreakpoints
        ; response.body["breakpoints"] := []
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

    setVariableRequest(response, env)
    {
        frameId := this._variableHandles.get(env.arguments.variablesReference)[2]
        try
            variable := this._runtime.SetVariable(env.arguments.name, frameId, env.arguments.value)
        catch err
        {
            response["body"] := {"error": CreateMessage(-1, err.Message . err.Extra)}
            return this.errorResponse(response, env)
        }
        response["body"] := {}
        response.body["value"] := variable.value
        , response.body["type"] := variable.type

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
			source := {"name": this.GetBaseFile(stack.file[A_Index]), "path": stack.file[A_Index], "sourceReference": 0+0, "adapterData": "mockdata"}
			stackFrames.Push({"id": stack.level[A_Index]+0, "name": stack.where[A_Index], "line": stack.line[A_Index]+0, "source": source, "column": 0}) ;
			; MsgBox, % fsarr().print(source)
		}
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
				; FIXME: problem in name is 'true' or 'false'
                variables.Push({"name": variablesRaw.name[A_Index]
                               ,"type": variablesRaw.type[A_Index]
                               ,"value": variablesRaw.type[A_Index] == "undefined" ? "<undefined>" : variablesRaw.value[A_Index]
                               ,"variablesReference"
							   : variablesRaw.type[A_Index] == "object" 
                               ? this._variableHandles.create([variablesRaw.fullName[A_Index], id[2]])+0 : 0})
                               ; ,"presentationHint": variablesRaw.facet == "Builtin" ? {"attributes": ["constant", "readOnly"]}})
                if variablesRaw.facet == "Builtin"
                    variables[A_Index]["presentationHint"] := {"attributes": ["constant", "readOnly"]}
            }
        }
		; MsgBox, % fsarr().print(variables)

        response["body"] := {"variables": variables}

        return [response]
    }

    continueRequest(response, env)
    {
        this._variableHandles.Reset()
        this._runtime.Continue()
        return [response]
    }

    nextRequest(response, env)
    {
		this._variableHandles.Reset()
        this._runtime.Next()
        return [response]
    }

    stepInRequest(response, env)
    {
		this._variableHandles.Reset()
        this._runtime.StepIn()
        return [response]
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
		return [response]
	}

    disconnectRequest(response, env)
    {
        this._runtime.DBGp_CloseDebugger(true)
		if Util_ProcessExist(this.Dbg_PID)
			Process, Close, % this.Dbg_PID
		this.isStart := false

        if ！env.arguments.restart
            env.server.keepRun := false  
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
