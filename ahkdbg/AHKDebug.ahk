#Include <JSON>
#Include <stdio>
#Include <handles>
#Include <event>
#Include ./protocolserver.ahk
#Include <application>
#Include ./AHKRuntime.ahk
#Include ./TokenTypeChecker.ahk

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
        this.metaVariableNames := ["class variables", "function variables"]
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
        response.body["supportsConfigurationDoneRequest"] := JSON.true
        response.body["supportsSetVariable"] := JSON.true
        response.body["supportsClipboardContext"] := JSON.true
        ; experimental features
        response.body["supportsHitConditionalBreakpoints"] := JSON.true
        ExceptionBreakpointsFilter := {"filter": "AHKExceptionBreakpoint"
                                    , "label": "Exceptions"
                                    , "description": "Breaks on all throw errors, even if they're caught later."
                                    , "default": JSON.False
                                    , "supportsCondition": JSON.False}
        ; let client know DA support exception breakpoint
        response.body["exceptionBreakpointFilters"] := [ExceptionBreakpointsFilter]
        ; response.body["supportsExceptionInfoRequest"] := JSON.True
        response.body["supportsEvaluateForHovers"] := JSON.true
        ; response.body["supportsFunctionBreakpoints"] := JSON.true
        ; response.body["supportsBreakpointLocationsRequest"] := JSON.true

        InitializedEvent := {"type": "event", "event": "initialized"}
        switch env.arguments.pathFormat
        {
            ; Only support 'path' Path Format
            case "path":
                this._runtime.Init(env.arguments)
            Default:
                response["body"] := {"error": CreateMessage(-1,env.arguments.program " launch fail`nInvalid path format`nOnly support path but pass format: " env.arguments.pathFormat)}
                return this.errorResponse(response, env)
        }
        return [response, InitializedEvent]
    }

    configurationDoneRequest(response, env)
    {
        this._configurationDone := true
        ; Eimt event to continue the response of launch request
        EventDispatcher.EmitImmediately("configurationDone", "")

        return [response]
    }

    launchRequest(response, env)
    {
        return this.HandleLaunch(response, env)
    }
    
    attachRequest(response, env) 
    {
        return this.HandleLaunch(response, env)
    }
    
    ; async exec
    HandleLaunch(response, env)
    {
        ; start ahk debug here
        if !this.isStart
        {
            if (env.arguments.AhkExecutable == "-1") 
            {
                response["body"] := {"error": CreateMessage(-1, "Invalid runtime is passed by language server. Please check interpreter settings")}
                return this.errorResponse(response, env)
            }
            this._runtime.dbgCaptureStreams := (env.arguments.captureStreams == JSON.true) ? true : false
            runtime := env.arguments.runtime == "" ? env.arguments.AhkExecutable : env.arguments.runtime
            this._runtime.AhkExecutable := FileExist(runtime) ? runtime : this._runtime.AhkExecutable
            result := ParsePort(env.arguments.port)
            if(result[1])
                this._runtime.portRange := result[2]
            else 
            {
                response["body"] := {"error": CreateMessage(-1, result[2] "`nReceived: '"  env.arguments.port "'. Please check interpreter settings")}
                return this.errorResponse(response, env)
            }
            noDebug := (env.arguments.noDebug == JSON.true) ? true : false
            DALogger.Init()
            try
            {
                if (env.command == "launch")
                    this._runtime.Start(env.arguments.program, env.arguments.args, noDebug)
                else
                    this._runtime.Attach(env.arguments.program)
            }
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
        if (!this._configurationDone and !this._timeout) ; 
        {
            server := env.server
            if (!this.isStart) 
            {
                CTO := ObjBindMethod(this, "CheckTimeOut")
                SetTimer, % CTO, -1000
            }
            ; Pause the respones of launch request by return empty
            ; Wait for configrationDone request to emit the event
            RR := ObjBindMethod(server, "ResumeRequest", env)
            EventDispatcher.On("configurationDone", RR)
            return
        }


        stopOnEntry := (env.arguments.stopOnEntry == JSON.true) ? true : false
        this._runtime.StartRun(stopOnEntry)

        return [response]
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
                actualBreakpoints.Push(CreateBreakpoint(bkp.verified, bkp.id, bkp.line+0, , source, bkp.message)) ;
            }
            catch err
            {
                source := {"name": this.GetBaseFile(path), "path": path, "sourceReference": 0+0}
                actualBreakpoints.Push(CreateBreakpoint(JSON.false,, bkinfo.line+0, 0, source, err.Extra))
            }
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

    setExceptionBreakpointsRequest(response, env) 
    {
        actualBreakpoints := []
        filters := env.arguments.filters
        ; we only support one filter type
        ; If have filter, it is request to set ExceptionBreakpoint
        bkp := this._runtime.SetExceptionBreakpoint(filters.Length() == 1)
        actualBreakpoints.Push(bkp)

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

    setVariableRequest(response, env)
    {
        frameId := this._variableHandles.get(env.arguments.variablesReference).frameId
        try
            variable := this._runtime.SetVariable(env.arguments.name, frameId, env.arguments.value)[1]
        catch err
        {
            response["body"] := {"error": CreateMessage(-1, err.Message . err.Extra)}
            return this.errorResponse(response, env)
        }
        response["body"] := {}
        response.body["value"] := (variable.type == "string") ? """" variable.value """" : variable.variable
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
        ; Since ahk always keeps two scopes(Local, Global), just return them
        response.body["scopes"] := [{"name": "Local", "variablesReference": this._variableHandles.create(new VarRefInfo("Local", frameId, true)), "expensive": JSON.false}
                                  , {"name": "Global", "variablesReference": this._variableHandles.create(new VarRefInfo("Global", "None", true)), "expensive": JSON.true}]
        return [response]
    }

    ; TODO: May long running, need async exec here
    variablesRequest(response, env)
    {
        ; Retrieve the identity information of request variable
        ; id : [variableFullName, its frameid]
        id := this._variableHandles.get(env.arguments.variablesReference)
        variables := []
        if (!id) {
            response["error"] := CreateMessage(-1, "Get an non-exist variable reference.")
            return this.errorResponse(response, env)
        }
        
        isGlobalScope := id.isMeta && id.fullName == "Global"
        ; EventDispatcher.EmitImmediately("send", CreateOutputEvent("stdout", "varref fullname: " id.fullName " frameId: " id.frameId))
        if (isGlobalScope) {
            additionalInfo := {}
            for _, metaName in this.metaVariableNames {
                additionalInfo[metaName] := []
            }
        }
        ; Return variable list
        variablesRaw := id.isMeta && IsInArray(this.metaVariableNames, id.fullName) ; if reference is a variables folding
                        ? id.addtional
                        : this._runtime.CheckVariableReference(id)
        for _, var in variablesRaw 
        {
            ; if (var.name = "true" or var.name = "false")
            ;     var.name .= " "

            if (var.type == "undefined")
                var.value := "<undefined>"
            else if (var.type == "string")
                var.value := """" var.value """"
                ; replace escape character to original form
                , var.value := StrReplace(var.value, "`n", "``n")
                , var.value := StrReplace(var.value, "`r", "``r")
                , var.value := StrReplace(var.value, "`t", "``t")
            ; FIXME: problem in name is 'true' or 'false'
            if (isGlobalScope && var.type == "object" && (var.value == "(Class)" || var.value == "Func")) {
                ; cache Global infomation
                if (var.value == "(Class)")
                    additionalInfo["class variables"].Push(var)
                if (var.value == "Func")
                    additionalInfo["function variables"].Push(var)
                continue
            }
            variables.Push({"name": var.name
                            ,"type": var.type
                            ,"value": var.value
                            ,"variablesReference"
                            : var.type == "object" 
                        ;    store fullname for inspecting
                            ? this._variableHandles.create(new VarRefInfo(var.fullName, id.frameId))+0 : 0})
                            ; ,"presentationHint": variablesRaw.facet == "Builtin" ? {"attributes": ["constant", "readOnly"]}})
            if var.facet == "Builtin"
                var["presentationHint"] := {"attributes": ["constant", "readOnly"]}
        }
        ; Global variables folding
        if (isGlobalScope) {
            for _, metaName in this.metaVariableNames {
                varRef := new VarRefInfo(metaName, "None", true)
                ; cache Global class infomation
                varRef.addtional := additionalInfo[metaName]
                variables.Push({"name": metaName
                              , "value": ""
                              , "variablesReference":this._variableHandles.create(varRef)+0})
            }
        }
        ; MsgBox, % fsarr().print(variables)

        response["body"] := {"variables": variables}

        return [response]
    }

    evaluateRequest(response, env) {
        if (!this.isStart) 
            return this.errorResponse(response, env)
        varName := env.arguments.expression
        frameId := env.arguments.frameId
        context := env.arguments.context
        body := {}
        if (context == "hover") {
            varType := TokenType(varName)
            if (varType != "id") {
                response.success := JSON.False
                response["body"] := body
                return [response]
            }
        }
        varibleInfo := this._runtime.EvaluateVariable(varName, frameId)
        ; logger(fsarr().print(varibleInfo))
        var_type := varibleInfo["type"]
        result := varibleInfo["value"]
        if (var_type == "undefined")
            result := "<undefined>"
        else if (var_type == "string")
            result := """" result """"
        body["result"] := result
        body["type"] := var_type
        body["variablesReference"] := var_type == "object" 
                                    ? this._variableHandles.create(new VarRefInfo(varibleInfo["fullName"], frameId)) : 0
        response["body"] := body

        return [response]
    }

    exceptionInfoRequest(response, env) {
        body := {}
        body["exceptionId"] := "AHKException"
        body["description"] := "Exception ocurrs"
        body["breakMode"] := "userUnhandled"
        ; body["details"] := {}
        response["body"] := body
        return [response, CreateOutputEvent("stdout", "exceptionInfoRequest")]
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
        if Util_ProcessExist(this._runtime.Dbg_PID)
            Process, Close, % this._runtime.Dbg_PID
        this.isStart := false

        if !env.arguments.restart
            env.server.keepRun := false  
        return [response]
    }

    errorResponse(response, env)
    {
        ; TODO: send error info here
        response.success := JSON.false
        return [response]
    }

    GetBaseFile(path)
    {
        SplitPath, % path, name
        return name
    }
}

; Function to validate if a port number is within the valid range
IsValidPort(Port) {
    return (Port >= 1 and Port <= 65535)
}

; Function to parse and validate a port number or range
ParsePort(Port) {
    Valid := False
    Result := ""

    ; If Port is an integer
    if (Port is Integer) {
        if IsValidPort(Port) {
            Valid := True
            Result := [Port, Port]
        } else {
            Result := "Error: Invalid port number. Must be between 1 and 65535."
        }
    } else if (Port is String) {
        ; Trim any spaces
        Port := Trim(Port)

        ; Check if it is a single port number represented as a string
        if RegExMatch(Port, "^\d+$") {
            PortNum := Port + 0 ; Convert to integer
            if IsValidPort(PortNum) {
                Valid := True
                Result := [PortNum, PortNum]
            } else {
                Result := "Error: Invalid port number. Must be between 1 and 65535."
            }
        } else if RegExMatch(Port, "^\d+\s*-\s*\d+$") {
            ; Remove any spaces around the dash
            Port := RegExReplace(Port, "\s*-\s*", "-")
            PortParts := StrSplit(Port, "-")
            StartPort := PortParts[1] + 0 ; Convert to integer
            EndPort := PortParts[2] + 0   ; Convert to integer

            if IsValidPort(StartPort) and IsValidPort(EndPort) {
                if (StartPort <= EndPort) {
                    Valid := True
                    Result := [StartPort, EndPort]
                } else {
                    Result := "Error: Start port must be less than or equal to end port."
                }
            } else {
                Result := "Error: Port numbers in the range must be between 1 and 65535."
            }
        } else {
            Result := "Error: Invalid input format."
        }
    } else {
        Result := "Error: Invalid input format."
    }

    return [Valid, Result]
}

IsInArray(arr, idx) {
    return (idx > 0 && idx <= arr.Length())
}
