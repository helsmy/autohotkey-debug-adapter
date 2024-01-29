TokenType(token) {
    static nonChar := "!""#$%&\'()*+,-./:;<=>?@[\\]^_``{|}~"
    static keyword := {if: "",else: "",switch: "",case: "",default: "",loop: "",for: "",in: "",while: "",until: "",break: "",continue: "",try: "",catch: "",finally: "",gosub: "",goto: "",return: "",global: "",local: "",throw: "",class: "",extends: "",new: "",static: ""}
    ; static keyword := {if, else, switch, case, loop,
    ;     for, in,
    ;     while, until, break, continue,
    ;     try, catch, finally,
    ;     gosub, goto, return, global,
    ;     local, throw, class,
    ;     extends, static,
    ;     byref}
    start := SubStr(token, 1, 1)
    if (start == """") 
        return "string"
    if token is Integer
        return "nteger"
    if token is Float
        return "float"
    if keyword.HasKey(token)
        return "keyword"
    if (InStr(nonChar, token))
        return "mark"
    return "id"
}