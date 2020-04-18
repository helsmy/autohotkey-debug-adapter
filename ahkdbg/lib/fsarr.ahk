/*  Lib about array and assciative array

arr := arr()

arr.cpy(arr)         Return a deep copy of an array

arr.swapKeyVar(arr)  Swap key and value of an assciative array

arr.print(arr)       Return an array in string form

*/

#Include <fstype>

fsarr()
{
	return __ClASS_AHKFS_ARRAY
}

class __ClASS_AHKFS_ARRAY
{
	;------------------------- copy -------------------------
	cpy(arr)
	{
		/*
			Return a deep copy of an array
			简介: 完全拷贝一个数组, 无法拷贝class中的方法, cpy = copy

			[1] arr {Array / Associative Array}	任意层级的数组

			返回值:	{Array / Associative Array}
					返回数组与源数组无引用关系
		*/
		local
		switch fstype(arr)
		{
			case "Array":
				ret := []
				for _,v in arr
				{
					if IsObject(arr)
						ret.Push(this.cpy(ret))
					ret.Push(v)
				}
			case "Associative Array":
				ret := {}
				for k,v in arr
				{
					if IsObject(arr)
						ret[k] := this.cpy(ret)
					ret[k] := v
				}
			Default:
				Throw Exception("Invaild Value! Need an array, but pass a(n) " . fstype(arr), -1)
		}
		return ret
	}
	;------------------------- swap -------------------------
	SwapKeyVal(arr)
	{
		/*
			Swap key and value of an Associative Array
			简介: 调换数组的键值对, 不建议多维复杂的数组使用

			[1] arr {Array / Associative Array}

			返回值: {Array / Associative Array}
		*/
		local
		if fstype(arr) != "Associative Array"
			Throw Exception("Invaild Value! Need an associative array, but pass a(n) " . fstype(array), -1)
		ret := {}
		for key, val in arr
			ret[val] := key
		return ret
	}
	;------------------------- debug -------------------------
	print(arr)
	{
		/*
			return an array in form of string. like below:
		    返回一个字符串形式的数组, 返回形式与ahk的定义形式相同, 如下:
				[items*, [items*], {key: value}, ……]
		*/
		local
		ret := ""
		switch fstype(arr)
		{
			case "Array":
				ret .= "["
				for _, v in arr
				{
					if IsObject(v)
						ret .= this.print(v) . ", "
					else if fstype(v) == "String"
					{
						v := StrReplace(v, "\" , "\\")
						v := StrReplace(v, """", "\""")
						ret .= """" . v . """" . ", "
					}
					else
						ret .= v . ", "
				}
				ret := (StrLen(ret)>1) ? SubStr(ret, 1, -2) : ret
				ret .= "]"
			case "Associative Array":
				ret .= "{"
				for k,v in arr
				{
					if IsObject(v)
						ret .= """" . k . """" . ": " . this.print(v) . ", "
					else if fstype(v) == "String"
					{
						v := StrReplace(v, "\" , "\\")
						; k := StrReplace(k, "\" , "\\")
						v := StrReplace(v, """", "\""")
						; k := StrReplace(k, """", "\""")
						ret .= """" . k . """" . ": " . """" . v . """" . ", "
					}
					else
						ret .= """" . k . """" . ": " . v . ", "
				}
				ret := (StrLen(ret)>1) ? SubStr(ret, 1, -2) : ret
				ret .= "}"
			Default:
				Throw Exception("Invaild Value! Need an array, but pass a(n) " . fstype(arr), -1)
		}
		return ret
	}
}
