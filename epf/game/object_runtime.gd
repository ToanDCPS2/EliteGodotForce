class_name ObjectRuntime
extends RefCounted
## One scripted room object: its own Lua VM (system prelude + the object's chunk), driven by events.
var vm: LuaVM
var fn: LuaVM.LuaFn
var obj_id: int
var name: String
var error := ""

static func create(world_chunks: Dictionary, system_bytes: PackedByteArray, chunk_bytes: PackedByteArray, api: GameApi, id: int, nm: String) -> ObjectRuntime:
	var r := ObjectRuntime.new(); r.obj_id = id; r.name = nm
	r.vm = LuaVM.new()
	LuaStdlib.install(r.vm, Callable())
	r.vm.G.set_v("_util", api.make_util(r.vm))
	r.vm.call_fn(LuaVM.load_chunk(system_bytes), [])
	r.fn = LuaVM.load_chunk(chunk_bytes)
	return r

## Fire one event reason (name in _const, e.g. "CREATED") then pump coroutines.
func fire(api: GameApi, reason: String, source: int = 0) -> bool:
	api.current_self = obj_id; api.current_source = source
	var consts = vm.G.get_v("_const")
	api.current_reason = consts.get_v(reason) if consts != null else 0
	vm.steps = 0
	vm.call_fn(fn, [])
	var rc = vm.G.get_v("runCoroutines")
	if rc != null:
		for _i in 3: vm.call_fn(rc, [])
	return true
