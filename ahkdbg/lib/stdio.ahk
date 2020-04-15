class StdIO
{
	__New()
	{
		this.inStream := FileOpen("*", "r")
	}

	Read()
	{
		return this.inStream.Read()
	}

	Write(text)
	{
		; Some problem in call write method of outStream
		; Raw write to stdout by fileappend
		FileAppend, % text, *
	}

	__Delete()
	{
		this.inStream.Close()
	}
}
