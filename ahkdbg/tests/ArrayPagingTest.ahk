; Unit tests for ArrayPaging.ahk (AutoHotkey v1).
; Run:  AutoHotkey.exe tests\ArrayPagingTest.ahk
; Output goes to stdout; pipe it (AutoHotkey is a GUI-subsystem app):
;   & .\bin\AutoHotkey.exe .\ahkdbg\tests\ArrayPagingTest.ahk | Out-Host

#NoEnv
#NoTrayIcon
#Include %A_ScriptDir%\..\ArrayPaging.ahk

g_pass := 0
g_fail := 0

Check(desc, actual, expected)
{
    global g_pass, g_fail
    if (actual == expected)
        g_pass++
    else
    {
        g_fail++
        FileAppend, % "FAIL: " desc "`n  expected: " expected "`n  actual:   " actual "`n", *
    }
}

; ---------- ArrPaging_B64ToInt ----------
Check("b64 400", ArrPaging_B64ToInt("NDAw"), 400)
Check("b64 0", ArrPaging_B64ToInt("MA=="), 0)
Check("b64 12345", ArrPaging_B64ToInt("MTIzNDU="), 12345)

; ---------- ArrPaging_TotalPages ----------
Check("pages L=400 n0=99", ArrPaging_TotalPages(400, 99, 100), 5)
Check("pages L=99 n0=99", ArrPaging_TotalPages(99, 99, 100), 1)
Check("pages L=100 n0=99", ArrPaging_TotalPages(100, 99, 100), 2)
Check("pages L=250 n0=99", ArrPaging_TotalPages(250, 99, 100), 3)

; ---------- ArrPaging_PageItemRange ----------
r := ArrPaging_PageItemRange(0, 99, 100, 400)
Check("page0 start", r[1], 1)
Check("page0 end", r[2], 99)
r := ArrPaging_PageItemRange(1, 99, 100, 400)
Check("page1 start", r[1], 100)
Check("page1 end", r[2], 199)
r := ArrPaging_PageItemRange(4, 99, 100, 400)
Check("last page start", r[1], 400)
Check("last page end", r[2], 400)
Check("page beyond end", ArrPaging_PageItemRange(5, 99, 100, 400) == "", 1)

; ---------- folding levels ----------
; L=400 -> 5 pages -> single level of page metas
metas := ArrPaging_RootMetas(400, 99, 100, "arr", 0)
Check("L400 root count", metas.Length(), 5)
Check("L400 first name", ArrPaging_MetaName(metas[1].itemStart, metas[1].itemEnd), "[1-99]")
Check("L400 second name", ArrPaging_MetaName(metas[2].itemStart, metas[2].itemEnd), "[100-199]")
Check("L400 last name", ArrPaging_MetaName(metas[5].itemStart, metas[5].itemEnd), "[400-400]")
Check("L400 leaf kind", metas[1].IsPage(), 1)

; L=1500 -> 16 pages -> two levels: 10-page groups
metas := ArrPaging_RootMetas(1500, 99, 100, "arr", 0)
Check("L1500 root count", metas.Length(), 2)
Check("L1500 group1 name", ArrPaging_MetaName(metas[1].itemStart, metas[1].itemEnd), "[1-999]")
Check("L1500 group2 name", ArrPaging_MetaName(metas[2].itemStart, metas[2].itemEnd), "[1000-1500]")
Check("L1500 group is not page", metas[1].IsPage(), 0)
children := ArrPaging_ChildMetas(metas[1])
Check("L1500 group1 children", children.Length(), 10)
Check("L1500 group1 first child", ArrPaging_MetaName(children[1].itemStart, children[1].itemEnd), "[1-99]")
Check("L1500 group1 last child", ArrPaging_MetaName(children[10].itemStart, children[10].itemEnd), "[900-999]")
children := ArrPaging_ChildMetas(metas[2])
Check("L1500 group2 children", children.Length(), 6)
Check("L1500 group2 last child", ArrPaging_MetaName(children[6].itemStart, children[6].itemEnd), "[1500-1500]")

; L=12000 -> 121 pages -> three levels: root spans 100 pages
metas := ArrPaging_RootMetas(12000, 99, 100, "arr", 0)
Check("L12000 root count", metas.Length(), 2)
Check("L12000 group1 name", ArrPaging_MetaName(metas[1].itemStart, metas[1].itemEnd), "[1-9999]")
mid := ArrPaging_ChildMetas(metas[2])
Check("L12000 level2 count", mid.Length(), 3)
Check("L12000 level2 last", ArrPaging_MetaName(mid[3].itemStart, mid[3].itemEnd), "[12000-12000]")
leaves := ArrPaging_ChildMetas(mid[2])
Check("L12000 full group leaves", leaves.Length(), 10)
Check("L12000 leaves first", ArrPaging_MetaName(leaves[1].itemStart, leaves[1].itemEnd), "[11000-11099]")
Check("L12000 leaves last", ArrPaging_MetaName(leaves[10].itemStart, leaves[10].itemEnd), "[11900-11999]")
leaves := ArrPaging_ChildMetas(mid[3])
Check("L12000 tail leaves", leaves.Length(), 1)
Check("L12000 tail leaf", ArrPaging_MetaName(leaves[1].itemStart, leaves[1].itemEnd), "[12000-12000]")

; page 0 with full 100 items (n0=100 case from goal.md)
r := ArrPaging_PageItemRange(1, 100, 100, 400)
Check("n0=100 page1 start", r[1], 101)
Check("n0=100 page1 end", r[2], 200)

; ---------- XML parsing (fixtures from goal.md) ----------
LoadFixture(name) {
    xmlText := ""
    FileRead, xmlText, % A_ScriptDir "\fixtures\" name
    dom := ComObjCreate("MSXML2.DOMDocument.6.0")
    dom.async := false
    dom.loadXML(xmlText)
    return dom
}

dom := LoadFixture("page0.xml")
info := ArrPaging_ParsePage0(dom)
Check("page0 foldable", info.foldable, 1)
Check("page0 Length", info.arrayLength, 400)
Check("page0 itemsInPage0", info.itemsInPage0, 99)
Check("page0 pagesize", info.pageSize, 100)

FileAppend, % g_pass " tests, " g_fail " failures`n", *
if (g_fail > 0)
    ExitApp 1
ExitApp 0
