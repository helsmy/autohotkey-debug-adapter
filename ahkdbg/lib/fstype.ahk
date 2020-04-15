/*
    return type of a certain obj
    Empty string "" is considered as None type

    Directly call

    reference: https://blog.csdn.net/liuyukuan/article/details/90545903
    
    Distinguish Array and Associative Array based on
        array's min index is 1 and array's index is continuous
    By default, an empty {} or [] is considered as an array

    只支持简单的类型判断
    在对象是一个类时返回字符串 "BaseObjectName"，如果基对象是数组或者关联数组则认为对象是一个数组或者关联数组
    问题：
         不支持判断 Inf -Inf NaN 等特殊的浮点类型，这些浮点类型应该会被当成字符串类型
*/


fstype(obj)
{
    local
    if IsObject(obj)
    {
        static nMatchObj  := NumGet(&(m, RegExMatch("", "O)", m)))
        static nBoundFunc := NumGet(&(f := Func("Func").Bind()))
        static nFileObj   := NumGet(&(f := FileOpen("*", "w")))
        static nEnumObj   := NumGet(&(e := ObjNewEnum({})))

        if obj.__class
            return obj.__class
        if ((objCount := obj.count()) == 0)
            return "Array"
        else if (objCount == obj.Length() && obj.MinIndex() == 1)
            return "Array"
        return IsFunc(obj)                ? "Func"
             : ComObjType(obj) != ""      ? "ComObject"
             : NumGet(&obj) == nBoundFunc ? "BoundFunc"
             : NumGet(&obj) == nMatchObj  ? "RegExMatchObject"
             : NumGet(&obj) == nFileObj   ? "FileObject"
             : NumGet(&obj) == nEnumObj   ? "Object::Enumerator"
             :                              "Associative Array"
    }

    if (obj == "")
        return "None"

    return obj := "" || [obj].GetCapacity(1) ? "String" : InStr(obj,".") ? "Float" : "Integer"
}