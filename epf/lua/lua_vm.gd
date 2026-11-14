class_name LuaVM
extends RefCounted
## Interpreter for the game's integer-only Lua 5.1 bytecode (header 1B 4C 75 61 51 00 01 04 04 04 04 01).
## Explicit frame stack (no GDScript recursion per Lua call) so coroutine.yield works from any Lua call depth.
## Numbers are 32-bit signed integers. Tables = LuaTable. nil = null. Native functions: Callable(args:Array)->Array.
## Reference implementation + differential tests: tools/epf_luavm.py.

class LuaTable:
	extends RefCounted
	var d: Dictionary = {}
	var meta = null  # Dictionary or null (supports "__index" only)
	func get_v(k): return d.get(k, null)
	func set_v(k, v):
		if v == null: d.erase(k)
		else: d[k] = v
	func length() -> int:
		var n := 0
		while d.has(n + 1): n += 1
		return n

class Proto:
	extends RefCounted
	var nups := 0
	var nparams := 0
	var vararg := 0
	var maxstack := 0
	var code: PackedInt64Array = PackedInt64Array()
	var consts: Array = []
	var protos: Array = []

class Upval:
	extends RefCounted
	var regs: Array = []   # frame registers while open
	var idx := 0
	var closed := false
	var val = null
	func get_v(): return val if closed else regs[idx]
	func set_v(v):
		if closed: val = v
		else: regs[idx] = v

class LuaFn:
	extends RefCounted
	var p: Proto
	var ups: Array = []

class Frame:
	extends RefCounted
	var fn: LuaFn
	var regs: Array = []
	var pc := 0
	var varargs: Array = []
	var open_ups: Dictionary = {}
	var ret_a := 0       # where to store results in the caller
	var ret_n := 0       # c field of the CALL (0 = multi)
	var multi_top := 0

class Coroutine:
	extends RefCounted
	var frames: Array = []
	var status := "suspended"
	var transfer: Array = []
	var started := false
	var fn = null
	var yielded := false

var G := LuaTable.new()
var cur_co = null
var max_steps := 5_000_000
var steps := 0

class LuaError:
	extends RefCounted
	var msg := ""

const MASK := 0xFFFFFFFF
static func wrap32(x: int) -> int:
	x &= MASK
	return x - 0x100000000 if x & 0x80000000 else x

static func truthy(v) -> bool:
	return v != null and not (typeof(v) == TYPE_BOOL and v == false)

# ------------------------------------------------------------------ loading
class Reader:
	extends RefCounted
	var b: PackedByteArray
	var p := 0
	func u8() -> int:
		var v := b[p]; p += 1; return v
	func u32() -> int:
		var v := b.decode_u32(p); p += 4; return v
	func s32() -> int:
		var v := b.decode_s32(p); p += 4; return v
	func string():
		var n := u32()
		if n == 0: return null
		var s := b.slice(p, p + n - 1).get_string_from_ascii(); p += n; return s

static func _func(r: Reader) -> Proto:
	var f := Proto.new()
	r.string(); r.u32(); r.u32()
	f.nups = r.u8(); f.nparams = r.u8(); f.vararg = r.u8(); f.maxstack = r.u8()
	var n := r.u32()
	f.code.resize(n)
	for i in n: f.code[i] = r.u32()
	n = r.u32()
	for i in n:
		var t := r.u8()
		match t:
			0: f.consts.append(null)
			1: f.consts.append(r.u8() != 0)
			3: f.consts.append(r.s32())
			4: f.consts.append(r.string())
			_: push_error("bad lua constant type %d" % t)
	n = r.u32()
	for i in n: f.protos.append(_func(r))
	n = r.u32()
	for i in n: r.u32()           # line info
	n = r.u32()
	for i in n: r.string(); r.u32(); r.u32()   # locvars
	n = r.u32()
	for i in n: r.string()        # upvalue names
	return f

static func load_chunk(bytes: PackedByteArray) -> LuaFn:
	var hdr := PackedByteArray([0x1b, 0x4c, 0x75, 0x61, 0x51, 0x00, 0x01, 0x04, 0x04, 0x04, 0x04, 0x01])
	if bytes.slice(0, 12) != hdr:
		push_error("unexpected Lua header"); return null
	var r := Reader.new(); r.b = bytes; r.p = 12
	var fn := LuaFn.new(); fn.p = _func(r)
	return fn

# ------------------------------------------------------------------ helpers
func index(t, k):
	if t is LuaTable:
		var v = t.d.get(k, null)
		if v == null and t.meta != null:
			var h = t.meta.get("__index", null)
			if h is LuaTable: return index(h, k)
			if h is Callable:
				var r: Array = h.call([t, k])
				return r[0] if r.size() > 0 else null
		return v
	push_error("attempt to index a non-table value")
	return null

func _eq(x, y) -> bool:
	var tx := typeof(x); var ty := typeof(y)
	if tx != ty: return false
	return x == y

func _num(x) -> int:
	if typeof(x) == TYPE_INT: return x
	if typeof(x) == TYPE_STRING and x.is_valid_int(): return int(x)
	push_error("attempt to perform arithmetic on a non-number")
	return 0

func _close_ups(f: Frame, from_reg: int) -> void:
	for idx in f.open_ups.keys():
		if idx >= from_reg:
			var u: Upval = f.open_ups[idx]
			u.val = f.regs[idx]; u.closed = true
			f.open_ups.erase(idx)

func _new_frame(fn: LuaFn, args: Array) -> Frame:
	var f := Frame.new(); f.fn = fn
	f.regs.resize(fn.p.maxstack + 2)
	for i in fn.p.nparams:
		f.regs[i] = args[i] if i < args.size() else null
	if fn.p.vararg != 0 and args.size() > fn.p.nparams:
		f.varargs = args.slice(fn.p.nparams)
	return f

# ------------------------------------------------------------------ public API
## Call fn with args from the host; returns result Array. Runs to completion (or until a coroutine yields to its resumer).
func call_fn(fn, args: Array) -> Array:
	if fn is Callable: return fn.call(args)
	if not (fn is LuaFn): push_error("attempt to call a non-function value"); return []
	var co := Coroutine.new()
	co.frames.append(_new_frame(fn, args)); co.started = true
	var saved = cur_co
	cur_co = co
	var res := _run(co)
	cur_co = saved
	return res

func _run(co: Coroutine) -> Array:
	var frames: Array = co.frames
	var top_result: Array = []
	var f: Frame = frames[frames.size() - 1]
	var code: PackedInt64Array = f.fn.p.code
	var K: Array = f.fn.p.consts
	var R: Array = f.regs
	while true:
		steps += 1
		if steps > max_steps:
			push_error("lua step limit"); return []
		var ins := code[f.pc]; f.pc += 1
		var op := ins & 0x3F
		var a := (ins >> 6) & 0xFF
		var c := (ins >> 14) & 0x1FF
		var b := (ins >> 23) & 0x1FF
		match op:
			0: R[a] = R[b]
			1: R[a] = K[ins >> 14]
			2:
				R[a] = (b != 0)
				if c != 0: f.pc += 1
			3:
				for i in range(a, b + 1): R[i] = null
			4: R[a] = f.fn.ups[b].get_v()
			5: R[a] = index(G, K[ins >> 14])
			6: R[a] = index(R[b], K[c - 256] if c >= 256 else R[c])
			7: G.set_v(K[ins >> 14], R[a])
			8: f.fn.ups[b].set_v(R[a])
			9:
				var kt = K[b - 256] if b >= 256 else R[b]
				var vt = K[c - 256] if c >= 256 else R[c]
				if not (R[a] is LuaTable): push_error("attempt to index a non-table value"); return []
				R[a].set_v(kt, vt)
			10: R[a] = LuaTable.new()
			11:
				var o = R[b]; R[a + 1] = o
				R[a] = index(o, K[c - 256] if c >= 256 else R[c])
			12, 13, 14, 15, 16, 17:
				var x := _num(K[b - 256] if b >= 256 else R[b])
				var y := _num(K[c - 256] if c >= 256 else R[c])
				var r := 0
				match op:
					12: r = x + y
					13: r = x - y
					14: r = x * y
					15:
						if y == 0: push_error("divide by zero"); return []
						r = absi(x) / absi(y)
						if (x < 0) != (y < 0): r = -r
					16:
						if y == 0: push_error("modulo by zero"); return []
						r = x - int(floor(float(x) / float(y))) * y
					17:
						r = int(pow(x, y)) if y >= 0 else 0
				R[a] = wrap32(r)
			18: R[a] = wrap32(-_num(R[b]))
			19: R[a] = not truthy(R[b])
			20:
				var lv = R[b]
				R[a] = lv.length() if lv is String else lv.length()
			21:
				var s := ""
				for i in range(b, c + 1): s += str(R[i])
				R[a] = s
			22: f.pc += (ins >> 14) - 131071
			23, 24, 25:
				var x = K[b - 256] if b >= 256 else R[b]
				var y = K[c - 256] if c >= 256 else R[c]
				var r := false
				match op:
					23: r = _eq(x, y)
					24: r = x < y
					25: r = x <= y
				if r != (a != 0): f.pc += 1
			26:
				if truthy(R[a]) != (c != 0): f.pc += 1
			27:
				if truthy(R[b]) != (c != 0): f.pc += 1
				else: R[a] = R[b]
			28, 29:
				var nargs := (b - 1) if b != 0 else (f.multi_top - a - 1)
				var cargs: Array = R.slice(a + 1, a + 1 + nargs)
				var callee = R[a]
				if callee is Callable:
					var res: Array = callee.call(cargs)
					if co.yielded:
						# native requested a yield (coroutine.yield): park here, results go back on resume
						f.ret_a = a; f.ret_n = c
						return []
					_store_results(f, a, c, res)
				elif callee is LuaFn:
					f.ret_a = a; f.ret_n = c
					var nf := _new_frame(callee, cargs)
					nf.ret_a = a; nf.ret_n = c
					frames.append(nf)
					f = nf; code = f.fn.p.code; K = f.fn.p.consts; R = f.regs
				else:
					push_error("attempt to call a non-function value"); return []
			30:
				var rets: Array
				if b == 0: rets = R.slice(a, f.multi_top)
				else: rets = R.slice(a, a + b - 1)
				_close_ups(f, 0)
				frames.pop_back()
				if frames.is_empty(): return rets
				var ra := f.ret_a; var rn := f.ret_n
				f = frames[frames.size() - 1]; code = f.fn.p.code; K = f.fn.p.consts; R = f.regs
				_store_results(f, ra, rn, rets)
			31:
				R[a] += R[a + 2]
				var st: int = R[a + 2]
				if (st > 0 and R[a] <= R[a + 1]) or (st <= 0 and R[a] >= R[a + 1]):
					R[a + 3] = R[a]; f.pc += (ins >> 14) - 131071
			32:
				R[a] = _num(R[a]) - _num(R[a + 2]); f.pc += (ins >> 14) - 131071
			33:
				var itf = R[a]
				var res: Array
				if itf is Callable: res = itf.call([R[a + 1], R[a + 2]])
				else: res = call_fn(itf, [R[a + 1], R[a + 2]])
				for i in c: R[a + 3 + i] = res[i] if i < res.size() else null
				if R[a + 3] != null: R[a + 2] = R[a + 3]
				else: f.pc += 1
			34:
				var n := b if b != 0 else (f.multi_top - a - 1)
				var base := (c - 1) * 50
				for i in range(1, n + 1): R[a].set_v(base + i, R[a + i])
			35: _close_ups(f, a)
			36:
				var sub: Proto = f.fn.p.protos[ins >> 14]
				var nf := LuaFn.new(); nf.p = sub
				for _i in sub.nups:
					var pi := code[f.pc]; f.pc += 1
					var pop := pi & 0x3F
					var pb := (pi >> 23) & 0x1FF
					if pop == 0:   # MOVE: capture a register of this frame
						var u: Upval = f.open_ups.get(pb, null)
						if u == null:
							u = Upval.new(); u.regs = R; u.idx = pb
							f.open_ups[pb] = u
						nf.ups.append(u)
					else:          # GETUPVAL
						nf.ups.append(f.fn.ups[pb])
				R[a] = nf
			37:
				var n := (b - 1) if b != 0 else f.varargs.size()
				for i in n: R[a + i] = f.varargs[i] if i < f.varargs.size() else null
				if b == 0: f.multi_top = a + f.varargs.size()
			_:
				push_error("unknown lua opcode %d" % op); return []
	return top_result

func _store_results(f: Frame, a: int, c: int, res: Array) -> void:
	var R: Array = f.regs
	if c == 0:
		for i in res.size(): R[a + i] = res[i]
		f.multi_top = a + res.size()
	else:
		for i in c - 1: R[a + i] = res[i] if i < res.size() else null

# ------------------------------------------------------------------ coroutines (explicit stacks => yield from any depth)
func co_create(fn) -> Coroutine:
	var co := Coroutine.new(); co.fn = fn
	return co

func co_resume(co: Coroutine, args: Array) -> Array:
	if co.status == "dead": return [false, "cannot resume dead coroutine"]
	var prev = cur_co
	cur_co = co; co.status = "running"; co.yielded = false
	var res: Array
	if not co.started:
		co.started = true
		if co.fn is Callable:
			res = co.fn.call(args); co.status = "dead"; cur_co = prev; return [true] + res
		co.frames.append(_new_frame(co.fn, args))
		res = _run(co)
	else:
		# deliver resume args as the results of the pending yield CALL, then continue
		var f: Frame = co.frames[co.frames.size() - 1]
		_store_results(f, f.ret_a, f.ret_n, args)
		co.yielded = false
		res = _run(co)
	cur_co = prev
	if co.yielded:
		co.status = "suspended"
		return [true] + co.transfer
	co.status = "dead"
	return [true] + res

func co_yield(args: Array) -> Array:
	if cur_co == null: push_error("attempt to yield from outside a coroutine"); return []
	cur_co.yielded = true; cur_co.transfer = args
	return []
