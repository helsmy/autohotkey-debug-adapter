; Array paging utilities for folding long arrays into meta variables.
; This file must stay dependency-free (no #Include of lib/) so it can be
; unit-tested standalone.

; Meta information of an array folding node, stored in VarRefInfo.addtional.
; kind = "arrayPage"  : a leaf node covering one DBGp page (itemStart..itemEnd)
; kind = "arrayGroup" : an inner node covering pageStart..pageEnd (10^n pages)
class ArrayMetaInfo
{
    __New(kind, pageStart, pageEnd, itemStart, itemEnd, arrayLength, itemsInPage0, pageSize, baseFullName, frameId) {
        this.kind := kind
        this.pageStart := pageStart
        this.pageEnd := pageEnd
        this.itemStart := itemStart
        this.itemEnd := itemEnd
        this.arrayLength := arrayLength
        this.itemsInPage0 := itemsInPage0
        this.pageSize := pageSize
        this.baseFullName := baseFullName
        this.frameId := frameId
    }

    IsPage() {
        return this.kind == "arrayPage"
    }
}

; Total number of DBGp pages of an array with arrayLength items,
; where page 0 carries itemsInPage0 items and every later page pageSize items.
ArrPaging_TotalPages(arrayLength, itemsInPage0, pageSize) {
    rest := arrayLength - itemsInPage0
    if (rest <= 0)
        return 1
    return 1 + Ceil(rest / pageSize)
}

; 1-based inclusive item range [start, end] covered by 0-based page `page`,
; or "" when the page is beyond the last page.
ArrPaging_PageItemRange(page, itemsInPage0, pageSize, arrayLength) {
    if (page == 0) {
        if (arrayLength < 1)
            return ""
        return [1, Min(itemsInPage0, arrayLength)]
    }
    start := itemsInPage0 + (page - 1) * pageSize + 1
    if (start > arrayLength)
        return ""
    end := Min(itemsInPage0 + page * pageSize, arrayLength)
    return [start, end]
}

ArrPaging_MetaName(itemStart, itemEnd) {
    return "[" itemStart "-" itemEnd "]"
}

; Smallest power of ten >= totalPages (the page span of root nodes).
; totalPages < 10 -> span 1 (pages are directly the root level).
ArrPaging_RootSpan(totalPages) {
    span := 1
    while (totalPages > span * 10)
        span *= 10
    return span
}

; Build the root meta list shown when expanding the array itself.
ArrPaging_RootMetas(arrayLength, itemsInPage0, pageSize, baseFullName, frameId) {
    totalPages := ArrPaging_TotalPages(arrayLength, itemsInPage0, pageSize)
    return ArrPaging_ChildMetasBySpan(0, totalPages - 1, ArrPaging_RootSpan(totalPages)
        , arrayLength, itemsInPage0, pageSize, baseFullName, frameId)
}

; Children of a group node covering pages pageStart..pageEnd where each
; child covers childSpan pages (childSpan = 1 -> page leaves).
ArrPaging_ChildMetasBySpan(pageStart, pageEnd, childSpan, arrayLength, itemsInPage0, pageSize, baseFullName, frameId) {
    children := []
    p := pageStart
    while (p <= pageEnd) {
        end := Min(p + childSpan - 1, pageEnd)
        r1 := ArrPaging_PageItemRange(p, itemsInPage0, pageSize, arrayLength)
        r2 := ArrPaging_PageItemRange(end, itemsInPage0, pageSize, arrayLength)
        kind := childSpan == 1 ? "arrayPage" : "arrayGroup"
        children.Push(new ArrayMetaInfo(kind, p, end, r1[1], r2[2], arrayLength, itemsInPage0, pageSize, baseFullName, frameId))
        p := end + 1
    }
    return children
}

; Children of a group meta (groups of ten, last one may be smaller).
ArrPaging_ChildMetas(meta) {
    if (meta.IsPage())
        return []
    span := meta.pageEnd - meta.pageStart + 1
    ; children use the next lower power of ten, so a partial final group
    ; (e.g. 21 pages) still splits into 10-page groups
    childSpan := 1
    while (childSpan * 10 < span)
        childSpan *= 10
    return ArrPaging_ChildMetasBySpan(meta.pageStart, meta.pageEnd, childSpan
        , meta.arrayLength, meta.itemsInPage0, meta.pageSize, meta.baseFullName, meta.frameId)
}

; Analyse a page-0 property_get DOM. Returns an object with:
;   foldable      - true when the array should be folded into meta variables
;   arrayLength   - item count taken from <base>.Length (0 when absent)
;   itemsInPage0  - item (non-<base>) properties contained in page 0
;   pageSize      - value of the pagesize attribute
ArrPaging_ParsePage0(dom) {
    root := dom.selectSingleNode("/response/property")
    info := {foldable: false, arrayLength: 0, itemsInPage0: 0, pageSize: 0}
    if (!root)
        return info
    classname := root.getAttribute("classname")
    if (classname != "Array")
        return info
    pageSize := root.getAttribute("pagesize") + 0
    items := 0
    propertyNodes := dom.selectNodes("/response/property[1]/property")
    Loop % propertyNodes.length
    {
        nodeName := propertyNodes.item[A_Index-1].getAttribute("name")
        if (nodeName != "<base>")
            items++
    }
    info.itemsInPage0 := items
    info.pageSize := pageSize
    lengthNode := dom.selectSingleNode("/response/property/property[@name='<base>']/property[@name='Length']")
    if (!lengthNode)
        return info
    length := ArrPaging_B64ToInt(lengthNode.text)
    info.arrayLength := length
    ; rule: arrays not longer than one page are not folded
    info.foldable := (length > pageSize && pageSize > 0 && items > 0)
    return info
}

; Decode a base64-encoded non-negative integer (e.g. Length "NDAw" -> 400).
; Standard base64: every 4 characters encode up to 3 bytes.
ArrPaging_B64ToInt(str) {
    static chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    decoded := ""
    idxs := []
    Loop, Parse, str
    {
        if (A_LoopField == "=")
            break
        idx := InStr(chars, A_LoopField, true) - 1
        if (idx < 0)
            return 0
        idxs.Push(idx)
        if (idxs.Length() == 4)
        {
            n := idxs[1] * 262144 + idxs[2] * 4096 + idxs[3] * 64 + idxs[4]
            decoded .= Chr(n >> 16 & 255) . Chr(n >> 8 & 255) . Chr(n & 255)
            idxs := []
        }
    }
    if (idxs.Length() > 0)
    {
        k := idxs.Length()
        num := 0
        Loop % k
            num := num * 64 + idxs[A_Index]
        bytes := k - 1
        num := num >> (6 * k - 8 * bytes)
        Loop % bytes
            decoded .= Chr((num >> (8 * (bytes - A_Index))) & 255)
    }
    return decoded + 0
}
