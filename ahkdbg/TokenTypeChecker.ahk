TokenType(token) {
    start := SubStr(token, 1, 1)
    if (start == """") 
        return "string"
    if token is Integer
        return "nteger"
    if token is Float
        return "float"
    return "id"
}