# AutoHotKey Debug

Simple debug adaptor for AutoHotKey implemented by AutoHotKey.

## Features

* Basic debug functions. Step into, step out, breakpoints etc.
* Show call stack and varibles.

## Using

1. Open an AutoHotKey source file.
2. Switch to the debug viewlet.
3. Press the green 'play' button to start debugging.

![Debug](images/debugging.gif)

## Supported Settings of Launch.json

* `stopOnEntry`: stop on entry or not.
* `captureStreams`: capture io streams or not.

## Known Issues

An early version which needs test. Use it at you own risk.
1. Breakpoint may can't set or cancel (solution: try set and cancel several times)

## Release Notes

### 0.0.3

Fix display bug in object

### 0.0.5

Support redirecting standard io streams to debug console. 

## Furture Plan

* [ ] Support Evaluate For Hovers
* [x] Support debug console
* [ ] Change value of varible in debugging
