#Include ./protocolserver.ahk
#Include ./AHKBKManger.ahk
#Include <DBGp>
#Include <event>
#Include <JSON>

class AHKRunTime
{
	static errorCodeToInfo := {1 :"parse error in command"
							, 2 :"duplicate arguments in command"
							, 3 :"invalid options"
							, 4 :"Unimplemented command"
							, 5 :"Command not available"
							, 100 :"can not open file"
							, 101 :"stream redirect failed"
							, 200 :"breakpoint could not be set"
							, 201 :"breakpoint type not supported"
							, 202 :"invalid breakpoint"
							, 203 :"no code on breakpoint line"
							, 204 :"Invalid breakpoint state"
							, 205 :"No such breakpoint"
							, 206 :"Error evaluating code"
							, 207 :"Invalid expression"
							, 300 :"Can not get property"
							, 301 :"Stack depth invalid"
							, 302 :"Context invalid"
							, 900 :"Encoding not supported"
							, 998 :"An internal exception in the debugger occurred"
							, 999 :"Unknown error"}
	__New()
	{
		this.dbgAddr := "127.0.0.1"
		this.dbgPort := 9005 ;temp mock debug port
		this.bIsAttach := false
		this.dbgCaptureStreams := false
		this.Dbg_Session := ""
		this.BkManger := new BreakPointManger()
		this.dbgMaxChildren := 99+0
		this.currline := 0
		this.isStart := false
		this.stoppedReason := "breakpoint"
		this.globalContextId := 1
		this.defaultExecutable := "C:\Program Files\AutoHotkey\AutoHotkey.exe"
		dfltExcutable := "C:\Program Files\AutoHotkey\AutoHotkey.exe"
		RegRead, ahkDir, HKEY_LOCAL_MACHINE\SOFTWARE\AutoHotkey, InstallDir
		ahkPath :=  ahkDir . "\Autohotkey.exe"
		this.AhkExecutable := FileExist(ahkPath) ? ahkPath : dfltExcutable
		EventDispatcher.On("debugeeBreak", ObjBindMethod(this, "OnBreak"))
	}

	Init(clientArgs)
	{
		; Set the DBGp event handlers
		DBGp_OnBegin(ObjBindMethod(this, "OnDebuggerConnection"))
		DBGp_OnBreak(ObjBindMethod(this, "OnDebuggerBreak"))
		DBGp_OnStream(ObjBindMethod(this, "OnDebuggerStream"))
		DBGp_OnEnd(ObjBindMethod(this, "OnDebuggerDisconnection"))
		; DBGp_OnAccept(ObjBindMethod(this, "OnDebuggerAccept"))
		this.clientArgs := clientArgs
		; DebuggerInit
	}

	; Start DBGp Server and connect to script
	Start(path, noDebug := false)
	{
		; Ensure that some important constants exist
		this.path := path, szFilename := path
		AhkExecutable := this.AhkExecutable
		dbgAddr := this.dbgAddr, dbgPort := this.dbgPort ? this.dbgPort : 9005
		SplitPath, szFilename,, szDir

		if noDebug
		{
			Run, "%AhkExecutable%" "%szFilename%", %szDir%
			this.DBGp_CloseDebugger(true)
			this.SendEvent(CreateTerminatedEvent())
			return
		}

		; Now really run AutoHotkey and wait for it to connect
		this.Dbg_Socket := DBGp_StartListening(dbgAddr, dbgPort) ; start listening
		; DebugRun
		Run, "%AhkExecutable%" /Debug=%dbgAddr%:%dbgPort% "%szFilename%", %szDir%,, Dbg_PID ; run AutoHotkey and store its process ID
		this.Dbg_PID := Dbg_PID

		timeout := 0
		while ((Dbg_AHKExists := Util_ProcessExist(Dbg_PID)) && this.Dbg_Session == "") ; wait for AutoHotkey to connect or exit
		{
			Sleep, 100 ; avoid smashing the CPU
			; timeout += 100
			; if (timeout == 1000)
			; 	throw Exception("Connection timeout", -1, "May get wrong path: " this.path)
		}	
		DBGp_StopListening(this.Dbg_Socket) ; stop accepting script connection
		this.isStart := true
		if (this.Dbg_Lang != "AutoHotkey")
		{
			; Resolve that debugger does not exit, when syntax error at start.
			; Why disconnection event is not sended under this situation?
			if (Util_ProcessExist(Dbg_PID))
				throw Exception("invaild language.", -1, this.Dbg_Lang)
			else
				this.SendEvent(CreateTerminatedEvent())
		}
        ; 立即取回子节点，设置了最大取回两层
        this.SetEnableChildren(true)
		this.BkManger.Dbg_Session := this.Dbg_Session
		; Pause
	}

	; Attach to script(@param program)
	Attach(program) {
		DetectHiddenWindows, On
		dbgAddr := this.dbgAddr, dbgPort := this.dbgPort ? this.dbgPort : 9005
		this.Dbg_Socket := DBGp_StartListening(dbgAddr, dbgPort) ; start listening

		; Find script to attach
		pid := Util_FindRunningProcessID(program)
		if (pid)
			; Reference: https://github.com/zero-plusplus/vscode-autohotkey-debug
			PostMessage DllCall("RegisterWindowMessage", "Str", "AHK_ATTACH_DEBUGGER"), DllCall("ws2_32\inet_addr", "astr", dbgAddr), dbgPort,, ahk_pid %pid%
		else
		{
			DBGp_StopListening(this.Dbg_Socket) ; Script not found, stop listening
			throw Exception("Fail to attach '" program "'", -1)
		}
		this.bIsAttach := true
		while (this.Dbg_Session == "")
		{
			sleep 100
		}
		DBGp_StopListening(this.Dbg_Socket) ; stop accepting script connection
		this.Dbg_PID := pid
		this.isStart := true
		this.SetEnableChildren(true)
		this.BkManger.Dbg_Session := this.Dbg_Session
		DetectHiddenWindows, Off
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
		this.stoppedReason := "step"
		this.Dbg_Session.step_into()
	}

	Next()
	{
		ErrorLevel = 0
		this.Dbg_OnBreak := false
		this.Dbg_HasStarted := true
		this.stoppedReason := "step"
		this.Dbg_Session.step_over()
	}

	StepOut()
	{
		ErrorLevel = 0
		this.Dbg_OnBreak := false
		this.Dbg_HasStarted := true
		this.stoppedReason := "step"
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
		; this.VerifyBreakpoints()
		if stopOnEntry
		{
			this.StepIn()
			; FIXME: don't hardcore thread id
			this.SendEvent(CreateStoppedEvent("entry", 1))
		}
		else
			this.Run()
	}

	Pause()
	{
		this.stoppedReason := "pause"
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
			MsgBox, 52, % this.path ", The script is running. Stopping it would mean loss of data. Proceed?"
			IfMsgBox, No
				return 0 ; fail
		}
		DBGp_OnEnd("") ; disable the DBGp OnEnd handler
		if this.bIsAsync || this.Dbg_OnBreak
		{
			; If we're on a break or the debugger is async we don't need to force the debugger to terminate
			this.Dbg_Session.stop()
				; throw Exception("Debug session stop fail.", -1)
			this.Dbg_Session.Close()
		}
		else ; nope, we're not on a break, kill the process
		{
			this.Dbg_Session.Close()
			Process, Close, %Dbg_PID%
		}
		this.Dbg_Session := ""
		return 1 ; success
	}

	; fired when we accept a connection socket.
	OnDebuggerAccept()
	{
		; only debug one script at one time
		; MsgBox, Call OnAccept
		DBGp_StopListening(this.Dbg_Session)
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
		session.property_set("-n A_DebuggerName -c 1 -- " DBGp_Base64UTF8Encode(this.clientArgs.clientID))
		; in case H version
		session.property_set("-n A_DebuggerName -c 2 -- " DBGp_Base64UTF8Encode(this.clientArgs.clientID))
		session.feature_set("-n max_data -v " this.dbgMaxData)
		this.SetEnableChildren(false)
		if this.dbgCaptureStreams
		{
			session.stdout("-c 1")
			session.stderr("-c 1")
		}
		session.feature_get("-n supports_async", response)
		this.bIsAsync := !!InStr(response, ">1<")
		; Really nothing more to do
	}

	; OnDebuggerBreak() - fired when we receive an asynchronous response from the debugger (including break responses).
	OnDebuggerBreak(session, ByRef response)
	{
		if this.bInBkProcess
		{
			; A breakpoint was hit while the script running and the SciTE OnMessage thread is
			; still running. In order to avoid crashing, we must delay this function's processing
			; until the OnMessage thread is finished.
			ODB := ObjBindMethod(this, "OnDebuggerBreak")
			EventDispatcher.Put(ODB, [session, response])
			return
		}

		EventDispatcher.EmitImmediately("debugeeBreak", response)
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

	OnBreak(response) {
		dom := loadXML(response) ; load the XML document that the variable response is
		status := dom.selectSingleNode("/response/@status").text ; get the status
		reason := dom.selectSingleNode("/response/@reason").text ; get the status
		; this.SendEvent(CreateOutputEvent("stdout", status))
		if (status = "break")
		{ ; this is a break response
			this.Dbg_OnBreak := true ; set the Dbg_OnBreak variable
			; Get info about the script currently running
			this.Dbg_GetStack()
			this.stoppedReason := "breakpoint"
			stopReason := this.stoppedReason

			; Normal Breakpoint, check if this breakpoint is conditional
			if (reason == "ok")
			{
				; soft way to implement conditional breakpoint
				; is it necessary to do this?
				; ahk itself even do not support this
				; though xdebug list it as one of core command ╮（﹀_﹀）╭
				if (this.IsNeedConditionalContiune())
				{
					this.Continue()
					return
				}
				this.SendEvent(CreateStoppedEvent(stopReason, DebugSession.THREAD_ID))
			}
			else
			{
				; if breakpoint is caused by exception, return reason
				; AHK会在异常断点时在reason里声明式什么类型的异常，返回即可
				; PATCH !!
				; 莫名其妙的被跳过了一行，什么神奇的bug哦，被timer发射的函数里还不能用reason为名的变量了？
				; 估计开个issue也不会修了，毕竟v1.1都deprecated了，也许该把这个项目切换到v2了
				stopReason := reason
				stopReason := reason
				this.SendEvent(CreateStoppedEvent(stopReason, DebugSession.THREAD_ID))
			}
		}
	}
	
	; @bkinfo: breakpoint infomation (dict of SourceBreakpoint)
	SetBreakpoint(path, bkinfo)
	{	
		uri := DBGp_EncodeFileURI(path)
		bk := this.GetBk(uri, bkinfo.line+0)
		if !this.isStart
			return {"verified": JSON.false, "line": line, "id": bk.id}

		; if breakpoint exists, update condition
		if !!bk
		{
			for cond, val in bkinfo
				bk["cond"][cond] := val
			this.EnableBK(bk.id)
			return {"verified": JSON.true, "line": bkinfo.line, "id": bk.id, "source": path}
		}
		
		; TODO: verify conditional breakpoint args 
		this.bInBkProcess := true
		this.Dbg_Session.breakpoint_set("-t line -n " bkinfo.line " -f " uri, Dbg_Response)
		If InStr(Dbg_Response, "<error") || !Dbg_Response ; Check if AutoHotkey actually inserted the breakpoint.
		{
			this.bInBkProcess := false
			; return reason to frontend
			dom := loadXML(Dbg_Response)
			errorCode := dom.selectSingleNode("/response/error/@code").text
			bkinfo := this.BkManger.addInvaild(DBGp_EncodeFileURI(path), bkinfo.line)
			return {"verified": JSON.false, "line": line, "id": bkinfo.id, "source": sourcePath, "message": this.errorCodeToInfo[errorCode]}
		}

		dom := loadXML(Dbg_Response)
		bkID := dom.selectSingleNode("/response/@id").text
		this.Dbg_Session.breakpoint_get("-d " bkID, Dbg_Response)
		dom := loadXML(Dbg_Response)
		line := dom.selectSingleNode("/response/breakpoint[@id=" bkID "]/@lineno").text
		;remove 'file:///' in begin, make uri format some
		sourceUri := SubStr(dom.selectSingleNode("/response/breakpoint[@id=" bkID "]/@filename").text, 9)
		sourcePath := DBGp_DecodeFileURI(sourceUri)
		this.BkManger.add(sourceUri, line, bkID, bkinfo)
		this.bInBkProcess := false

		return {"verified": JSON.true, "line": line, "id": bkID, "source": sourcePath}
	}

	/**
	 * @param enable {bool} enable ExceptionBreakpoint or not
	 */
	SetExceptionBreakpoint(enable) 
	{
		; Is ExceptionBreakpoint enabled. start at false.
		static isEnable := false
		; breakpoint id of ExceptionBreakpoint
		static bkid := ""

		if (!isEnable) 
		{
			; Set to disable and already disable
			if (!enable)
				return {"verified": JSON.false}
			this.bInBkProcess := true
			this.Dbg_Session.breakpoint_set("-t exception", Dbg_Response)
			If InStr(Dbg_Response, "<error") || !Dbg_Response ; Check if AutoHotkey actually inserted the breakpoint.
			{
				this.bInBkProcess := false
				; return reason to frontend
				dom := loadXML(Dbg_Response)
				errorCode := dom.selectSingleNode("/response/error/@code").text
				return {"verified": JSON.false, "message": this.errorCodeToInfo[errorCode]}
			}
			this.bInBkProcess := false
			dom := loadXML(Dbg_Response)
			bkid := dom.selectSingleNode("/response/@id").text
			isEnable := true
			return {"verified": JSON.true, "id": bkid}
		}
		else
		{
			; Set to enable and already enable
			if (enable)
				return {"verified": JSON.true, "id": bkid}
			return this.BkManger.removeId(bkid)
		}
	}

	DeleteBreakpoint(path, bkCheckDict)
	{
		uri := DBGp_EncodeFileURI(path)
		try 
			bkinfo := this.BkManger.Get(uri).Clone()
		catch error
			return
		
		for line in bkinfo
		{
			if !bkCheckDict.HasKey(line)
				this.RemoveBk(uri, line)
		}
	}

	VerifyBreakpoints(path)
	{
		uri := DBGp_EncodeFileURI(path)
		
		for line, bk in this.BkManger.get(uri)
			this.SendEvent(CreateBreakpointEvent("changed", CreateBreakpoint(JSON.true, bk.id, line, , path)))
	}

	IsNeedConditionalContiune()
	{
		stack := this.GetStack()
		uri := DBGp_EncodeFileURI(stack.file[1]), line := stack.line[1] & -1
		bkinfo := this.GetBk(uri, line), condition := bkinfo.cond
		if (condition.Count() > 1)
		{
			for cmd, param in condition
			{
				Switch cmd
				{
					Case "hitCondition":
						hitCount := condition.hitCount ? condition.hitCount : 1
						this.BkManger.UpdataBk(uri, line, "hitCount", hitCount+1)
						; this.sendEvent(CreateOutputEvent("stdout", hitCount))
						if (hitCount != param)
							return true
						else
						{
							this.DisableBk(uri, line)
							return false
						}
				}
			}
		}

		return false
	}

	InspectVariable(Dbg_VarName, frameId)
	{
		; Allow retrieving immediate children for object values
		if (this.enableChildren == false)
			this.SetEnableChildren(true)
		if (frameId != "None")
			this.Dbg_Session.property_get("-n " . Dbg_VarName . " -d " . frameId, Dbg_Response)
		else
		; context id of a global variable is 1
			this.Dbg_Session.property_get("-c " this.globalContextId " -n " Dbg_VarName, Dbg_Response)
		logger(Dbg_Response)
		; this.SetEnableChildren(false)
		dom := loadXML(Dbg_Response)

		Dbg_NewVarName := dom.selectSingleNode("/response/property/@name").text
		if Dbg_NewVarName = (invalid)
		{
			MsgBox, 48, %g_appTitle%, Invalid variable name: %Dbg_VarName%
			return false
		}
		if ((type := dom.selectSingleNode("/response/property/@type").text) != "Object")
		{
			Dbg_VarIsReadOnly := (dom.selectSingleNode("/response/property/@facet").text = "Builtin")
			Dbg_VarData := DBGp_Base64UTF8Decode(dom.selectSingleNode("/response/property").text)
			Dbg_VarData := [{"name": Dbg_NewVarName, "value": Dbg_VarData, "type": type}]
			;VE_Create(Dbg_VarName, Dbg_VarData, Dbg_VarIsReadOnly)
		}
		else
			Dbg_VarData := this.GetObjectInfoFromDom(dom, frameId)

		return Dbg_VarData
	}

	; Entry of variable request
	; id - name or id restored in variable handle
	; frameId - where stack frame of this variable loacated
	CheckVariables(id, frameId)
	{
		if (this.enableChildren == false)
			this.SetEnableChildren(true)
		if (id == "Global")
			id := "-c " this.globalContextId
		else if (id == "Local")
			id := "-d " . frameId . " -c 0"
		else
			return this.InspectVariable(id, frameId)
		; TODO: may need to send error
		; if !this.bIsAsync && !this.Dbg_OnBreak

		this.Dbg_Session.context_get(id, ScopeContext)
		logger(ScopeContext)
		; H version store global in context id=2
		; and no extra feature_name can be used to 
		; confirm H version
		if (!InStr(ScopeContext, "</property>") && id == "-c 1") {
			this.globalContextId := 2
			this.Dbg_Session.context_get("-c 2", ScopeContext)
		}
		logger(ScopeContext)
		return this.UnpackFrameVar(loadXML(ScopeContext), frameId)
	}

	GetObjectInfoFromDom(ByRef objdom, frameId)
	{
		root := objdom.selectSingleNode("/response/property/@name").text
		; logger(A_ThisFunc ": " root)
		; this.sendEvent(CreateOutputEvent("stdout", root))
		propertyNodes := objdom.selectNodes("/response/property[1]/property")
		
		variables := []
		
		Loop % propertyNodes.length
		{
			node := propertyNodes.item[A_Index-1]
			nodeName := node.attributes.getNamedItem("name").text
			needToLoadChildren := node.attributes.getNamedItem("children").text
			; Fuck! bug due to ahk itself
			nodeFullName := node.attributes.getNamedItem("fullname").text
			fixedFullName := ""
			for _, objKey in StrSplit(nodeFullName, ".")
			{
				if objKey is number
				{
					objKey := "[""" objKey """]"
					fixedFullName .= objKey
				}
				else
					fixedFullName .= "." objKey
			}
			nodeFullName := SubStr(fixedFullName, 2) 
			; this.sendEvent(CreateOutputEvent("stdout", nodeFullName))
			nodeType := node.attributes.getNamedItem("type").text
			if (nodeType == "object")
			{
				; we are checking the A_Index item of second layer of property
				; respone
				;    └---property <-- layer 1
				;           └---property
				;           └---property <-- object item(need to unpack)
				;                  └---property <-- we needed
				nodeValue := Util_UnpackObjValue(node, A_Index, 2)
			}
			else
				nodeValue := DBGp_Base64UTF8Decode(node.text)
			; nodeValue := (nodeType == "object") ? "(Object)" : DBGp_Base64UTF8Decode(node.text)
			variables.Push({  "name": nodeName
							, "type": nodeType
							, "value": nodeValue
							, "fullName": nodeFullName})
		}

		return variables
	}

	EvaluateVariable(id, frameId) 
	{
		if (frameId != "None")
			this.Dbg_Session.property_get("-n " id " -d "  frameId, Dbg_Response)
		else
		; context id of a global variable is 1
			this.Dbg_Session.property_get("-c " this.globalContextId " -n " id, Dbg_Response)

		dom := loadXML(Dbg_Response)
		; this.SendEvent(CreateOutputEvent("stdout", Dbg_Response))

		VarName := dom.selectSingleNode("/response/property/@name").text
		VarFullName := dom.selectSingleNode("/response/property/@fullname").text
		VarData := DBGp_Base64UTF8Decode(dom.selectSingleNode("/response/property").text)
		VarType := dom.selectSingleNode("/response/property/@type").text
		if (VarType == "object")
		{
			; select varible node for value unpack
			VarData := Util_UnpackObjValue(dom.selectSingleNode("/response/property"))
		}
		return {"name": VarName, "fullname": VarFullName, "value": VarData, "type": VarType}
	}

	SetVariable(varFullName, frameId, value)
	{	
		type := this.GetValueType(value)
		if (type == "integer")
			value := trim(value) & -1
		else if (type == "string")
		{
			value := SubStr(value, 2, -1)
			value := StrReplace(value, """""", """")
			value := StrReplace(value, "``r", "`r")
			value := StrReplace(value, "``t", "`t")
			value := StrReplace(value, "``n", "`n")
			value := StrReplace(value, "````", "``")
		}
		else if (type == "mark")
			type := "string"
		if (frameId != "None")
			cmd := "-n " varFullName " -d " frameId " -t " type " -- "
		else
		; context id of a global variable is 1
			cmd := "-c " this.globalContextId " -n " varFullName " -t " type " -- "

		this.Dbg_Session.property_set(cmd . DBGp_Base64UTF8Encode(value), Dbg_Response)
		if !InStr(Dbg_Response, "success=""1""")
			throw Exception("Set fail!", -1, "Variable may be immutable.")
		return this.InspectVariable(varFullName, frameId)
	}

	SetEnableChildren(v)
	{
		Dbg_Session := this.Dbg_Session
		dbgMaxChildren := this.dbgMaxChildren
		this.enableChildren := v
		if v
		{
			Dbg_Session.feature_set("-n max_children -v " dbgMaxChildren)
			Dbg_Session.feature_set("-n max_depth -v 2")
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
		aStackLevel := Util_UnpackNodes(this.Dbg_Stack.selectNodes("/response/stack/@level"))
		for i, file in aStackFile
			aStackFile[i] := DBGp_DecodeFileURI(file)

		return {"file": aStackFile, "line": aStackLine, "where": aStackWhere, "level": aStackLevel}
	}

	GetStackDepth()
	{
		this.Dbg_Session.stack_depth( , Dbg_Response)
		startpos := InStr(Dbg_Response, "depth=""")+7
		, depth := SubStr(Dbg_Response, startpos, InStr(Dbg_Response,"""", ,startpos) - startpos)
		return depth
	}

	GetScopeNames()
	{
		if this.Dbg_Session.context_names("", response) != 0
			throw Exception("Xdebug error", -1, ErrorLevel)
		dom := loadXML(response)
		contexts := dom.selectNodes("/response/context/@name")
		scopes := []
		Loop % contexts.length
		{
			context := contexts.item[A_Index-1].text
			scopes.Push(context)
		}
		return scopes
	}

	EnableBK(bkid)
	{
		this.Dbg_Session.breakpoint_update("-s enabled -d " bkID, Dbg_Response)
	}

	DisableBk(uri, line)
	{
		bkID := this.BkManger.get(uri, line)["id"]
		this.Dbg_Session.breakpoint_update("-s disabled -d " bkID, Dbg_Response)
		this.SendEvent(CreateBreakpointEvent("changed", CreateBreakpoint(JSON.false, bkID, line)))
	}

	RemoveBk(uri, line)
	{
		; this.SendEvent(CreateOutputEvent("stdout", "remove: " line))
		bkID := this.BkManger.get(uri, line)["id"]
		this.BkManger.remove(uri, line)
		this.SendEvent(CreateBreakpointEvent("changed", CreateBreakpoint(JSON.false, bkID, line)))
	}

	SendEvent(event)
	{
		EventDispatcher.EmitImmediately("sendEvent", event)
	}

	GetValueType(v)
	{
		if SubStr(v, 1, 1) == """" && SubStr(v, StrLen(v)) == """"
			return "string"
		if v is integer
			return "integer"
		if v is Float
			return "float"
		return "mark"
	}

	UnpackFrameVar(frameNode, frameid)
	{
		o := []
		variables :=  frameNode.DocumentElement.childNodes
		; this.SendEvent(CreateOutputEvent("stdout", "var count:" variables.length))
		for node in variables
		{	
			; this.SendEvent(CreateOutputEvent("stdout", "Node xml: `n" node.XML))
			; node := variables.item[A_Index-1]
			name := node.getAttribute("name")
			fullName := node.getAttribute("fullname")
			type := node.getAttribute("type")
			facet := node.getAttribute("facet")
			value := ""

			if (type != "object")
				value := DBGp_Base64UTF8Decode(node.text)
			else 
				value := Util_UnpackObjValue(frameNode.selectSingleNode("/response/property[" A_Index "]"), A_Index)

			o.Push({name: name, fullName: fullName, type: type, facet: facet, value: value})
		}
		; this.SendEvent(CreateOutputEvent("stdout", JSON.dump(o)))
		return o
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

Util_UnpackObjValue(ByRef node, index := 1, layer := 1) 
{
	classname := node.attributes.getNamedItem("classname").text
	queryStr := "/response"
	loop % layer
		queryStr .= "/property"
	queryStr .= "[" index "]/property"
	switch classname
	{
		case "Object":
			if (node.attributes.getNamedItem("children").text == "0")
				return "[]"
			propertyNodes := node.selectNodes(queryStr)
			; Set default type of v1 object to array
			t := "Array"
			; Distinguish array based on array has continuous index and max index is equal to max count
			loop % propertyNodes.length
			{
				node := propertyNodes.item[A_Index-1]
				nodeName := node.attributes.getNamedItem("name").text 
				if (SubStr(nodeName, 1, 1) == "[" && SubStr(nodeName, 0) == "]")
				{
					i := SubStr(nodeName, 2, StrLen(nodeName)-2)
					if !(i == A_Index)
					{
						t := "Map"
						break
					}
					continue
				}
				t := "Map"
				break
			}
			return Util_PropertyNodesObjToStr(propertyNodes, t)
		case "Class":
			return "(Class)"
		case "Array", "Map":
			logger(A_ThisFunc ": " node.attributes.getNamedItem("name").text )
			propertyNodes := node.selectNodes(queryStr)
			return Util_PropertyNodesObjToStr(propertyNodes, classname)
		default:
			return classname
	}
}

Util_PropertyNodesObjToStr(ByRef propertyNodes, type)
{
	start := type == "Array" ? "[" : "{"
	, end := type == "Array" ? "]" : "}"
	, s := start
	, c := Min(10, propertyNodes.length) ; TODO: configable max display number
	if (type == "Array") 
	{
		loop % c-1
		{
			; skip object base
			node := propertyNodes.item[A_Index-1]
			if (node.attributes.getNamedItem("name").text == "<base>")
				continue
			s .= Util_NodeTextToStr(node) ", "
		}
		node := propertyNodes.item[c-1]
		if (c < propertyNodes.length)
			s .= "..." end
		else
			s .= node.attributes.getNamedItem("name").text == "<base>" ? end
			     : Util_NodeTextToStr(node) end
	}
	else 
	{
		loop % c-1
		{
			; skip object base
			node := propertyNodes.item[A_Index-1]
			if (node.attributes.getNamedItem("name").text == "<base>")
				continue
			s .= Util_NodeNameToMapKey(node) ": " Util_NodeTextToStr(node) ", "
		}
		node := propertyNodes.item[c-1]
		if (c < propertyNodes.length)
			s .= "..." end
		else
			s .= node.attributes.getNamedItem("name").text == "<base>" ? end
			     : Util_NodeNameToMapKey(node) ": " Util_NodeTextToStr(node) end
	}
	return s
}

Util_NodeTextToStr(ByRef node)
{
	switch node.attributes.getNamedItem("type").text
	{
		case "string":
			return """" DBGp_Base64UTF8Decode(node.text) """"
		case "integer", "float":
			return DBGp_Base64UTF8Decode(node.text)
		case "object":
		; we only display one layer, so return a ...
			if (node.attributes.getNamedItem("classname").text == "Array")
				return "[...]"
			return "{...}"
		default:
			; MsgBox % node.attributes.getNamedItem("name").text
		; TODO: send error message to vscode
			; MsgBox % DBGp_Base64UTF8Decode(node.text)
			stack := ""
			loop 5 
				stack .= Exception("",-1-A_Index).What "`n"
			MsgBox % stack
			throw Exception("Wrong respone node type: " node.attributes.getNamedItem("type").text, -1, stack)
	}
}

Util_NodeNameToMapKey(ByRef node)
{
	name := node.attributes.getNamedItem("name").text
	; [number] is a number key
	if (SubStr(name, 1, 1) == "[" && SubStr(name, 0) == "]")
		return SubStr(name, 2, StrLen(name)-2)
	; other is a string key
	; TODO: handle object key in v2
	return """" name """"
}

; 找到对应路径的进程的PID
Util_FindRunningProcessID(path)
{
	; process property reference: https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process#properties
	for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process") 
	{
		; process start with "AutoHotkey"
		if (InStr(proc.name, "AutoHotkey", true) == 1) 
		{
			commandLine := proc.CommandLine
			if (InStr(commandLine, path)) 
				return proc.ProcessId
		}
	}
}

ST_ShortName(a)
{
	SplitPath, a, b
	return b
}

loadXML(ByRef data)
{
	o := ComObjCreate("MSXML2.DOMDocument.6.0")
	o.async := false
	o.validateOnParse := false
	o.setProperty("SelectionLanguage", "XPath")
	o.loadXML(data)
	return o
}

DummyCallback(session, ByRef response)
{

}

class VarInfo {
	__New(name, fullName, value, type, facet := "") {
		this.name := name
		this.fullName := fullName
		this.value := value
		this.type := type
		this.facet := facet
	}
}