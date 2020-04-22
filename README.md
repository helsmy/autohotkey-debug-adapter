# AutoHotKey Debug

Simple debug adapter for AutoHotKey implemented by AutoHotKey.

## Features

* Basic debug functions. Step into, step out, breakpoints etc.
* Show call stack and varibles.
* Debug ahkv2 since debug protocol do not change.(by set AhkExecutable path to v2 in launch.json)

## Using

1. Open an AutoHotKey source file.
2. Switch to the debug viewlet.
3. Press the green 'play' button to start debugging.

![Debug](images/debugging.gif)

## Supported Settings of Launch.json

* `stopOnEntry`: stop on entry or not.
* `captureStreams`: capture io streams or not.
* `AhkExecutable`: change Default Execute Path(by default is `C:\Program Files\Autohotkey\AutoHotkey.exe`).

## Known Issues

An early version which needs test. Use it at you own risk.
1. Unsupport for non-ascii characters.
2. ~~Breakpoint may can't set or cancel~~ (solution: fixed)

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

1. Use inner ahk
2. Add config option AhkExecutable

## Furture Plan

* [ ] Support Evaluate For Hovers
* [x] Support debug console
* [ ] Change value of varible in debugging
