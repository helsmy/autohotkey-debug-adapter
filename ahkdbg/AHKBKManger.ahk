class BreakPointManger {
    __New() {
        ; BkDict -- uri
		;         └- line
		;          └- id, cond(bkinfo) 
        this.bkDict := {}
        this.invaildBreakPointIdCount := 0
        this.Dbg_Session := ""
    }

    get(uri, line := "") {
        if (line == "")
            return this.bkDict[uri]
        return this.bkDict[uri, line]
    }

    add(uri, line, id, cond := "") {
        this.bkDict[uri, line+0] := { "id": id, "cond": cond}
        return this.bkDict[uri, line+0]
    }

    addInvaild(uri, line) {
        this.invaildBreakPointIdCount += 1
        id := -this.invaildBreakPointIdCount
        bkinfo := { "id": id, "cond": cond}
        this.bkDict[uri, line+0] := { "id": id, "cond": cond}
        return bkinfo
    }

    UpdataBk(uri, line, prop, value)
	{
		this.bkDict[uri, line, "cond", prop] := value
	}

    remove(uri, line := "") {
        if (line == "") {
            for line, bk in this.bkDict[uri] 
                this.removeOne(uri, line)
            this.bkDict[uri] := ""
        }
        this.removeOne(uri, line)
    }

    removeOne(uri, line) {
        bk := this.bkDict[uri, line+0]
        if (bk.id > 0)
            this.Dbg_Session.breakpoint_remove("-d " bk.id)
        this.bkDict[uri, line+0] := ""
    }

    removeId(id) {
        this.Dbg_Session.breakpoint_remove("-d " id)
        verified := JSON.False
        return {"id": id, "verified": verified}

    }
}