class Application
{
    App(instance, env)
    {
		if this.server
			this.server := instance
        return this.Router(env)
    }

    BuildApp()
    {
        return ObjBindMethod(this, "App")
    }

	Router(env)
	{
		; Dispatch task here
		handlerName := env.command . "Request"
		; Build response
		response := {}
		response["type"] := "response"
		; Fuck weakly typed!
		response["request_seq"] := env.seq+0
		response["success"] := JSON.true
		response["command"] := env.command
		; MsgBox % handlerName
		if !!this[handlerName]
			return this[handlerName](response, env)
		else  ;May need to send Error to frontend?
			return this.errorResponse(response, env)
	}
}
