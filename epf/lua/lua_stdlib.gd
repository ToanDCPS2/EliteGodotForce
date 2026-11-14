class_name LuaStdlib
extends RefCounted
## Subset of the Lua 5.1 standard library used by the game's scripts (see tools/epf_luavm.py install_stdlib).

static func install(vm: LuaVM, print_hook: Callable = Callable()) -> void:
	var G: LuaVM.LuaTable = vm.G
	G.set_v("print", func(a: Array) -> Array:
		if print_hook.is_valid(): print_hook.call(a)
		return [])
	G.set_v("ipairs", func(a: Array) -> Array:
		var t: LuaVM.LuaTable = a[0]
		var it := func(b: Array) -> Array:
			var i: int = b[1] + 1
			var v = t.get_v(i)
			return [i, v] if v != null else [null]
		return [it, t, 0])
	G.set_v("pairs", func(a: Array) -> Array:
		var t: LuaVM.LuaTable = a[0]
		var keys: Array = t.d.keys()
		var pos := [0]
		var it := func(b: Array) -> Array:
			if pos[0] >= keys.size(): return [null]
			var k = keys[pos[0]]; pos[0] += 1
			return [k, t.d.get(k)]
		return [it, t, null])
	G.set_v("type", func(a: Array) -> Array:
		var v = a[0] if a.size() > 0 else null
		if v == null: return ["nil"]
		match typeof(v):
			TYPE_BOOL: return ["boolean"]
			TYPE_INT: return ["number"]
			TYPE_STRING: return ["string"]
		if v is LuaVM.LuaTable: return ["table"]
		if v is LuaVM.Coroutine: return ["thread"]
		return ["function"])
	G.set_v("tonumber", func(a: Array) -> Array:
		var v = a[0]
		if typeof(v) == TYPE_INT: return [v]
		if typeof(v) == TYPE_STRING and v.is_valid_int(): return [int(v)]
		return [null])
	G.set_v("tostring", func(a: Array) -> Array:
		var v = a[0]
		if typeof(v) == TYPE_BOOL: return ["true" if v else "false"]
		if v == null: return ["nil"]
		return [str(v)])
	G.set_v("assert", func(a: Array) -> Array:
		if not LuaVM.truthy(a[0] if a.size() > 0 else null):
			push_error(str(a[1]) if a.size() > 1 else "assertion failed!")
		return a)
	G.set_v("error", func(a: Array) -> Array:
		push_error(str(a[0]) if a.size() > 0 else "error"); return [])
	G.set_v("select", func(a: Array) -> Array:
		if typeof(a[0]) == TYPE_STRING and a[0] == "#": return [a.size() - 1]
		return a.slice(a[0]))
	G.set_v("unpack", func(a: Array) -> Array:
		var t: LuaVM.LuaTable = a[0]; var out: Array = []
		for i in range(1, t.length() + 1): out.append(t.get_v(i))
		return out)
	G.set_v("pcall", func(a: Array) -> Array:
		return [true] + vm.call_fn(a[0], a.slice(1)))
	var T := LuaVM.LuaTable.new()
	T.set_v("insert", func(a: Array) -> Array:
		var t: LuaVM.LuaTable = a[0]
		if a.size() == 2: t.set_v(t.length() + 1, a[1])
		else:
			var n := t.length(); var pos: int = a[1]
			for i in range(n, pos - 1, -1): t.set_v(i + 1, t.get_v(i))
			t.set_v(pos, a[2])
		return [])
	T.set_v("remove", func(a: Array) -> Array:
		var t: LuaVM.LuaTable = a[0]; var n := t.length()
		var pos: int = a[1] if a.size() > 1 else n
		var v = t.get_v(pos)
		for i in range(pos, n): t.set_v(i, t.get_v(i + 1))
		t.set_v(n, null)
		return [v])
	T.set_v("getn", func(a: Array) -> Array: return [a[0].length()])
	T.set_v("concat", func(a: Array) -> Array:
		var t: LuaVM.LuaTable = a[0]; var sep: String = a[1] if a.size() > 1 else ""
		var parts: PackedStringArray = []
		for i in range(1, t.length() + 1): parts.append(str(t.get_v(i)))
		return [sep.join(parts)])
	G.set_v("table", T)
	var S := LuaVM.LuaTable.new()
	S.set_v("len", func(a: Array) -> Array: return [a[0].length()])
	S.set_v("lower", func(a: Array) -> Array: return [a[0].to_lower()])
	S.set_v("upper", func(a: Array) -> Array: return [a[0].to_upper()])
	S.set_v("sub", func(a: Array) -> Array:
		var s: String = a[0]; var j: int = a[2] if a.size() > 2 else s.length()
		return [s.substr(a[1] - 1, j - a[1] + 1)])
	G.set_v("string", S)
	var M := LuaVM.LuaTable.new()
	M.set_v("floor", func(a: Array) -> Array: return [a[0]])
	M.set_v("abs", func(a: Array) -> Array: return [absi(a[0])])
	M.set_v("max", func(a: Array) -> Array: return [a.max()])
	M.set_v("min", func(a: Array) -> Array: return [a.min()])
	G.set_v("math", M)
	var C := LuaVM.LuaTable.new()
	C.set_v("create", func(a: Array) -> Array: return [vm.co_create(a[0])])
	C.set_v("resume", func(a: Array) -> Array: return vm.co_resume(a[0], a.slice(1)))
	C.set_v("yield", func(a: Array) -> Array: return vm.co_yield(a))
	C.set_v("status", func(a: Array) -> Array: return [a[0].status])
	C.set_v("wrap", func(a: Array) -> Array:
		var co := vm.co_create(a[0])
		return [func(b: Array) -> Array:
			var r := vm.co_resume(co, b)
			return r.slice(1)])
	G.set_v("coroutine", C)
