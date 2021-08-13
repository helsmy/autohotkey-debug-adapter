#SingleInstance, Force
#KeyHistory, 0
SetBatchLines, -1

FileAppend, Hello stdout 0`nHello stdout 1`nHello stdout 2`n, *
OutputDebug, Hello stderr 0`nHello stderr 1`nHello stderr 2`n