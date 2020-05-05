# AutoHotKey Debug

Simple debug adapter for AutoHotKey implemented by AutoHotKey.

## Features

* Basic debug functions. Step into, step out, breakpoints etc.
* Show call stack and varibles.
* Debug ahkv2 since debug protocol do not change.(by set AhkExecutable path to v2 in launch.json)

## Using

1. Open an AutoHotKey source file.
2. For most simple way, press f5 to debug it.
3. If you want to start at a specific setting. Switch to the debug viewlet.
4. Press the green 'play' button, if vs code doesn't find launch.json, it will creat one for you. Save it and switch back to ahk file you open.
5. Press the green button again, debugger will start.

![Debug](images/debugging.gif)

## Supported Settings of Launch.json

* `type`: always ahkdbg.
* `request`: always launch.
* `name`: name of a specific setting.
* `program`: script file to be debugged(by default is file under editing).
* `stopOnEntry`: stop on entry or not.
* `captureStreams`: capture io streams or not.
* `AhkExecutable`: change Default Execute Path(by default is automaticlly acquired through registry, usualy is  `C:\Program Files\Autohotkey\AutoHotkey.exe`).
* `port`: The port on which to listen for XDebug (default: 9005)

## Known Issues

An early version which needs test. Use it at you own risk.
1. Unsupport for non-ascii characters.
2. ~~Breakpoint may can't set or cancel~~ (solution: fixed)

## Furture Plan

* [ ] Support Evaluate For Hovers
* [x] Support debug console
* [ ] Change value of varible in debugging

## Release Notes

### 0.0.3

Fix display bug in object

### 0.0.5

Support redirecting standard io streams to debug console.

### 0.1.0

1. Fix bugs abort breakpoints.
2. Support viewing variables in different stacks.

### 0.1.1

1. Fix display bugs.

### 0.2.0

1. Disconnect correctly(able to restart).
2. Fix pause request.

### 0.2.1

1. Use inner ahk.
2. Add config option AhkExecutable.

### 0.3.0

1. Autodetect ahk executable.
2. Fix stopped reason display.

### 0.3.1

1. Improve undefined variable display.
