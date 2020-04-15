; Useless

class ProtocolMessage
{
	__New()
	{

	}
}

class Response
{
	__New(request_seq, command)
	{
		; Needn't to care seq, it is set by server
		this.type := "response"
		this.request_seq := request_seq
		this.success := true
		this.command := command
	}

	SetBody(key, val)
	{
		if this.HasKey("body")
			this.body[key] := val
		else
		{
			this.body := {}
			this.body[key] := val
		}
	}

	SetMessage(str)
	{
		this.message := str
	}
}
