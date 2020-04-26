#Include <protocolserver>
#Include <DBGp>
#Include <event>

class AHKRunTime
{
	__New()
	{
		this.dbgAddr := "127.0.0.1"
		this.dbgPort := 9005 ;temp mock debug port
		this.bIsAttach := false
		this.dbgCaptureStreams := false
		RegRead, ahkpath, HKEY_CLASSES_ROOT\AutoHotkeyScript\DefaultIcon
		this.AhkExecutable := SubStr(ahkpath, 1, -2)
		this.Dbg_Session := ""
		this.Dbg_BkList := {}
		this.dbgMaxChildren := 10+0
		this.currline := 0
		this.isStart := false
	}

	Init(clientArgs)
	{
		; Set the DBGp event handlers
		DBGp_OnBegin(ObjBindMethod(this, "OnDebuggerConnection"))
		DBGp_OnBreak(ObjBindMethod(this, "OnDebuggerBreak"))
		DBGp_OnStream(ObjBindMethod(this, "OnDebuggerStream"))
		DBGp_OnEnd(ObjBindMethod(this, "OnDebuggerDisconnection"))
		this.clientArgs := clientArgs
		; DebuggerInit
	}

	Start(path)
	{
		; Ensure that some important constants exist
		this.path := path, szFilename := path,AhkExecutable := this.AhkExecutable ? this.AhkExecutable : "C:\Program Files\AutoHotkey\AutoHotkey.exe"
		dbgAddr := this.dbgAddr, dbgPort := this.dbgPort ? this.dbgPort : 9005
		; Now really run AutoHotkey and wait for it to connect
		this.Dbg_Socket := DBGp_StartListening(dbgAddr, dbgPort) ; start listening
		; DebugRun
		Run, "%AhkExecutable%" /Debug=%dbgAddr%:%dbgPort% "%szFilename%", %szDir%,, Dbg_PID ; run AutoHotkey and store its process ID
		this.Dbg_PID := Dbg_PID

		while ((Dbg_AHKExists := Util_ProcessExist(Dbg_PID)) && this.Dbg_Session == "") ; wait for AutoHotkey to connect or exit
			Sleep, 100 ; avoid smashing the CPU
		DBGp_StopListening(this.Dbg_Socket) ; stop accepting script connection
	}

	GetPath()
	{
		SplitPath, % this.path,, dir
		return StrReplace(dir, "\", "\\")
	}

	GetBaseFile()
	{
		SplitPath, % this.path, name
		return name
	}

	Continue()
	{
		this.Run()
	}

	StepIn()
	{
		ErrorLevel = 0
		this.Dbg_OnBreak := false
		this.Dbg_HasStarted := true
		this.Dbg_Session.step_into()
	}

	Next()
	{
		ErrorLevel = 0
		this.Dbg_OnBreak := false
		this.Dbg_HasStarted := true
		this.Dbg_Session.step_over()
	}

	StepOut()
	{
		ErrorLevel = 0
		this.Dbg_OnBreak := false
		this.Dbg_HasStarted := true
		this.Dbg_Session.step_out()
	}

	Run()
	{
		ErrorLevel = 0
		this.Dbg_OnBreak := false
		this.Dbg_HasStarted := true
		this.Dbg_Session.run()
	}

	StartRun(stopOnEntry := false)
	{
		this.VerifyBreakpoints()
		if stopOnEntry
		{
			this.StepIn()
			this.SendEvent(CreateStoppedEvent("entry", 1))
		}
		else
			this.Run()
	}

	Pause()
	{
		this.Dbg_Session.Send("break", "", Func("DummyCallback"))
	}

	Dbg_GetStack()
	{
		if !this.Dbg_OnBreak && !this.bIsAsync
			return
		this.Dbg_Session.stack_get("", Dbg_Stack := "")
		this.Dbg_Stack := loadXML(Dbg_Stack)
	}

	; DBGp_CloseDebugger() - used to close the debugger
	DBGp_CloseDebugger(force := 0)
	{
		if !this.bIsAsync && !force && !this.Dbg_OnBreak
		{
			MsgBox, 52, %g_appTitle%, The script is running. Stopping it would mean loss of data. Proceed?
			IfMsgBox, No
				return 0 ; fail
		}
		DBGp_OnEnd("") ; disable the DBGp OnEnd handler
		if this.bIsAsync || this.Dbg_OnBreak
		{
			; If we're on a break or the debugger is async we don't need to force the debugger to terminate
			if this.Dbg_Session.stop() != 0
				throw Exception("Debug session stop fail.", -1)
			this.Dbg_Session.Close()
		}else ; nope, we're not on a break, kill the process
		{
			this.Dbg_Session.Close()
			Process, Close, %Dbg_PID%
		}
		this.Dbg_Session := ""
		return 1 ; success
	}

	; OnDebuggerConnection() - fired when we receive a connection.
	OnDebuggerConnection(session, init)
	{
		; may need another param to pass the instance of object this function will bind to.
		if this.bIsAttach
			szFilename := session.File
		this.Dbg_Session := session ; store the session ID in a global variable
		dom := loadXML(init)
		this.Dbg_Lang := dom.selectSingleNode("/init/@language").text
		session.property_set("-n A_DebuggerName -- " DBGp_Base64UTF8Encode(this.clientArgs.clientID))
		session.feature_set("-n max_data -v " this.dbgMaxData)
		this.SetEnableChildren(false)
		if this.dbgCaptureStreams
		{
			session.stdout("-c 2")
			session.stderr("-c 2")
		}
		session.feature_get("-n supports_async", response)
		this.bIsAsync := !!InStr(response, ">1<")
		; Really nothing more to do
	}

	; OnDebuggerBreak() - fired when we receive an asynchronous response from the debugger (including break responses).
	OnDebuggerBreak(session, ByRef response)
	{
		global Dbg_OnBreak, Dbg_Stack, Dbg_LocalContext, Dbg_GlobalContext, Dbg_VarWin, bInBkProcess, _tempResponse

		if this.bInBkProcess
		{
			; A breakpoint was hit while the script running and the SciTE OnMessage thread is
			; still running. In order to avoid crashing, we must delay this function's processing
			; until the OnMessage thread is finished.
			_tempResponse := response
			ODB := ObjBindMethod(this, "OnDebuggerBreak")
			; TryHandlingBreakAgain, Send fucntion to Event Queue
			; SetTimer, TryHandlingBreakAgain, -100
			EventDispatcher.PutDelay(ODB, [session, response])
			return
		}
		response := response ? response : _tempResponse
		dom := loadXML(response) ; load the XML document that the variable response is
		status := dom.selectSingleNode("/response/@status").text ; get the status
		if status = break
		{ ; this is a break response
			this.Dbg_OnBreak := true ; set the Dbg_OnBreak variable
			; Get info about the script currently running
			this.Dbg_GetStack()
			; TODO: Send StopEvent to vscode
			this.SendEvent(CreateStoppedEvent("breakpoint", 1))
		}

	}

	; OnDebuggerStream() - fired when we receive a stream packet.
	OnDebuggerStream(session, ByRef stream)
	{
		dom := loadXML(stream)
		type := dom.selectSingleNode("/stream/@type").text
		data := DBGp_Base64UTF8Decode(dom.selectSingleNode("/stream").text)
		; Send output event
		this.SendEvent(CreateOutputEvent(type, data))
	}

	; OnDebuggerDisconnection() - fired when the debugger disconnects.
	OnDebuggerDisconnection(session)
	{
		global
		Critical

		Dbg_ExitByDisconnect := true ; tell our message handler to just return true without attempting to exit
		Dbg_ExitByGuiClose := true
		Dbg_IsClosing := true
		Dbg_OnBreak := true
		this.SendEvent(CreateTerminatedEvent())
	}

	clearBreakpoints(path)
	{
		uri := DBGp_EncodeFileURI(this.path)
		for line, bk in this.Dbg_BkList[uri]
			this.Dbg_Session.breakpoint_remove("-d " bk.id)
		; MsgBox, % line " " fsarr().Print(bk)
		this.Dbg_BkList[uri] := {}
		; this.Dbg_Session.breakpoint_list(, Dbg_Response)
		; MsgBox, % Dbg_Response " " fsarr().Print(this.Dbg_BkList)
	}

	; @line: 1 based lineno
	SetBreakpoint(path, line)
	{
		uri := DBGp_EncodeFileURI(this.path)
		bk := this.GetBk(uri, line)
		; if bk
		; {
			; this.Dbg_Session.breakpoint_remove("-d " bk.id)
			; response vs code here
			; SciTE_BPSymbolRemove(line)
			; this.RemoveBk(uri, line)
		; 	return {"verified": "true", "line": line, "id": bk.id}
		; }else
		; {
		this.bInBkProcess := true
		this.Dbg_Session.breakpoint_set("-t line -n " line " -f " uri, Dbg_Response)
		If InStr(Dbg_Response, "<error") ; Check if AutoHotkey actually inserted the breakpoint.
		{
			; MsgBox, Set error
			this.bInBkProcess := false
			; TODO: return reason to frontend
			return {"verified": "false", "line": line, "id": ""}
		}
		;MsgBox, Set success
		dom := loadXML(Dbg_Response)
		bkID := dom.selectSingleNode("/response/@id").text
		this.Dbg_Session.breakpoint_get("-d " bkID, Dbg_Response)
		dom := loadXML(Dbg_Response)
		line := dom.selectSingleNode("/response/breakpoint[@id=" bkID "]/@lineno").text
		this.AddBk(uri, line, bkID)
		this.bInBkProcess := false
		return {"verified": "true", "line": line, "id": bkID}
		; }
	}

	VerifyBreakpoints()
	{
		uri := DBGp_EncodeFileURI(this.path)
		for line, bk in this.Dbg_BkList[uri]
			this.SendEvent(CreateBreakpointEvent("changed", CreateBreakpoint("true", bk.id, line)))
	}

	InspectVariable(Dbg_VarName, frameId)
	{
		; Allow retrieving immediate children for object values
		this.SetEnableChildren(true)
		if (frameId != "None")
			this.Dbg_Session.property_get("-n " . Dbg_VarName . " -d " . frameId, Dbg_Response)
		else
			this.Dbg_Session.property_get("-n " Dbg_VarName, Dbg_Response)
		this.SetEnableChildren(false)
		dom := loadXML(Dbg_Response)

		Dbg_NewVarName := dom.selectSingleNode("/response/property/@name").text
		if Dbg_NewVarName = (invalid)
		{
			MsgBox, 48, %g_appTitle%, Invalid variable name: %Dbg_VarName%
			return false
		}
		if dom.selectSingleNode("/response/property/@type").text != "Object"
		{
			Dbg_VarIsReadOnly := dom.selectSingleNode("/response/property/@facet").text = "Builtin"
			Dbg_VarData := DBGp_Base64UTF8Decode(dom.selectSingleNode("/response/property").text)
			;VE_Create(Dbg_VarName, Dbg_VarData, Dbg_VarIsReadOnly)
		}else
			Dbg_VarData := this.InspectObject(dom)

		return Dbg_VarData
	}

	CheckVariables(id, frameId)
	{
		if (id == "Global")
			id := "-c 1"
		else if (id == "Local")
			id := "-d " . frameId . " -c 0"
		else
			return this.InspectVariable(id, frameId)
		; TODO: may need to send error
		; if !this.bIsAsync && !this.Dbg_OnBreak

		this.Dbg_Session.context_get(id, ScopeContext)
		ScopeContext := loadXML(ScopeContext)
		name := Util_UnpackNodes(ScopeContext.selectNodes("/response/property/@name"))
		value := Util_UnpackContNodes(ScopeContext.selectNodes("/response/property"))
		type := Util_UnpackNodes(ScopeContext.selectNodes("/response/property/@type"))
		facet := Util_UnpackNodes(ScopeContext.selectNodes("/response/property/@facet"))

		return {"name": name, "value": value, "type": type, "facet": facet}
	}

	InspectObject(ByRef objdom)
	{
		root := objdom.selectSingleNode("/response/property/@name").text
		propertyNodes := objdom.selectNodes("/response/property[1]/property")
		
		name := [], value := [], type := []
		
		Loop % propertyNodes.length
		{
			node := propertyNodes.item[A_Index-1]
			nodeName := node.attributes.getNamedItem("name").text
			needToLoadChildren := node.attributes.getNamedItem("children").text
			fullName := node.attributes.getNamedItem("fullname").text
			nodeType := node.attributes.getNamedItem("type").text
			nodeValue := DBGp_Base64UTF8Decode(node.text)
			name.Push(fullName), type.Push(nodeType), value.Push(nodeValue)
		}
		; TODO: better display name
		return {"name": name, "value": value, "type": type}
	}

	SetEnableChildren(v)
	{
		Dbg_Session := this.Dbg_Session
		dbgMaxChildren := this.dbgMaxChildren
		if v
		{
			Dbg_Session.feature_set("-n max_children -v " dbgMaxChildren)
			Dbg_Session.feature_set("-n max_depth -v 1")
		}else
		{
			Dbg_Session.feature_set("-n max_children -v 0")
			Dbg_Session.feature_set("-n max_depth -v 0")
		}
	}

	GetStack()
	{
		aStackWhere := Util_UnpackNodes(this.Dbg_Stack.selectNodes("/response/stack/@where"))
		aStackFile  := Util_UnpackNodes(this.Dbg_Stack.selectNodes("/response/stack/@filename"))
		aStackLine  := Util_UnpackNodes(this.Dbg_Stack.selectNodes("/response/stack/@lineno"))
		aStackLevel  := Util_UnpackNodes(this.Dbg_Stack.selectNodes("/response/stack/@level"))
		Loop, % aStackFile.Length()
			aStackFile[A_Index] := DBGp_DecodeFileURI(aStackFile[A_Index])

		return {"file": aStackFile, "line": aStackLine, "where": aStackWhere, "level": aStackLevel}
	}

	AddBk(uri, line, id, cond := "")
	{
		this.Dbg_BkList[uri, line] := { "id": id, "cond": cond }
	}

	GetBk(uri, line)
	{
		return this.Dbg_BkList[uri, line]
	}

	RemoveBk(uri, line)
	{
		this.Dbg_BkList[uri].Delete(line)
	}

	SendEvent(event)
	{
		EventDispatcher.EmitImmediately("sendEvent", event)
	}

	__Delete()
	{
		DBGp_StopListening(this.Dbg_Socket)
		this.DBGp_CloseDebugger()
		if Util_ProcessExist(this.Dbg_PID)
			Process, Close, % this.Dbg_PID
	}
}

; //////////////////////// Util Function ///////////////////////
Util_ProcessExist(a)
{
	t := ErrorLevel
	Process, Exist, %a%
	r := ErrorLevel
	ErrorLevel := t
	return r
}

Util_UnpackNodes(nodes)
{
	o := []
	Loop, % nodes.length
		o.Insert(nodes.item[A_Index-1].text)
	return o
}

Util_UnpackContNodes(nodes)
{
	o := []
	Loop, % nodes.length
		node := nodes.item[A_Index-1]
		,o.Insert(node.attributes.getNamedItem("type").text != "object" ? DBGp_Base64UTF8Decode(node.text) : "(Object)")
	return o
}

ST_ShortName(a)
{
	SplitPath, a, b
	return b
}

loadXML(ByRef data)
{
	o := ComObjCreate("MSXML2.DOMDocument")
	o.async := false
	o.setProperty("SelectionLanguage", "XPath")
	o.loadXML(data)
	return o
}

DummyCallback(session, ByRef response)
{

}
