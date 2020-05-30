
CreateStoppedEvent(reason, threadId)
{ 
	return {"type": "event", "event": "stopped", "body": {"reason": reason, "threadId": threadId}}
}

CreateBreakpointEvent(reason, breakpoint)
{
	return {"type": "event", "event": "breakpoint", "body": {"reason": reason, "breakpoint": breakpoint}}
}

CreateTerminatedEvent(restart := "")
{
	event := {"type": "event", "event": "terminated"}
	restart := restart ? "true"
	if restart == "true"
		event["body"] := {"restart": restart}
	return event
}

CreateExitedEvent(code := 0)
{
	return {"type": "event", "event": "exited", "body": {"exitCode": code+0}}
} 

CreateOutputEvent(category, output)
{
	return {"type": "event", "event": "output", "body": {"category": category, "output": output "`n"}}
}

CreateBreakpoint(verified, id := "", line := "", column := "", source := "")
{
	breakpoint := {}
	breakpoint["verified"] := verified
	if id is number
		breakpoint["id"] := id+0
	if line is number
		breakpoint["line"] := line+0
	if column is number
		breakpoint["column"] := column+0
	if source
		breakpoint["source"] := source
	return breakpoint
}
