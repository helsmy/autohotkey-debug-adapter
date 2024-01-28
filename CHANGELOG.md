## Release Notes

### 0.7.2

1. support `ExceptionBreakpoint`.
2. support `EvaluateForHovers`.
3. fix A_debuggerName dose not always set on global.

### 0.7.1

1. use win32 process com to aquire the pid of script to attach
2. better way to hanlde launch request
3. better way for non-block reading stdin

### 0.7.0
1. attach request
2. improve async respone by adding `ResumeRequest` method
3. use compressed exe to reduce size

### 0.6.0

1. improve event queue
2. conditional breakpoint(experimental) (0.6.1)
3. improve display (0.6.3)
4. fix bugs
5. fix bug about that debugee forever stopped when debugger stepin at return of hotkey (0.6.5)
6. global error catch and fix bug about run without debug (0.6.7)
7. change display about string (0.6.8)
8. fix bugs about display and breakpoint across file (0.6.9)
9. array and dict preview (0.6.11)
10. improve speed of inspecting object (0.6.11)
11. fix global variables can't display in H version (0.6.13)
12. fix bugs when variable contains control character
13. implement evaluate request (0.6.16)

### 0.5.0

1. change varibles in debugging
2. utf-8 support
3. support rewrite varibles with type

### 0.4.0

1. run without debug
2. fix breakpoints bugs in cross file(0.4.1)

### 0.3.0

1. Autodetect ahk executable.
2. Fix stopped reason display.
3. Improve undefined variable display.(0.3.1)

### 0.2.0

1. Disconnect correctly(able to restart).
2. Fix pause request.
3. Use inner ahk.(0.2.1)
4. Add config option AhkExecutable.(0.2.1)

### 0.1.0

1. Fix bugs abort breakpoints.
2. Support viewing variables in different stacks.
3. Fix display bugs.(0.1.1)


### 0.0.5

Support redirecting standard io streams to debug console.

### 0.0.3

Fix display bug in object
