
CreateStoppedEvent(reason, threadId)
{
	stoppedEvent := {"type": "event", "event": "stopped", "body": {"reason": reason, "threadId": threadId}}
	return stoppedEvent
}

CreateBreakpointEvent(reason, breakpoint)
{
	breakpointEvent := {"type": "event", "event": "breakpoint", "body": {"reason": reason, "breakpoint": breakpoint}}
	return breakpointEvent
}

CreateTerminatedEvent(restart := "")
{
	event := {"type": "event", "event": "terminated"}
	restart := restart ? "true"
	if restart == "true"
		event["body"] := {"restart": restart}
	return event
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
