extends SceneTree
## godot --headless --path . -s tests/probe_scripts.gd -- <out_dir> <result.json> [start] [count]
## Runs the game's 'system' prelude + every chunk under each event reason against a recording mock `_util`,
## same procedure as tools/epf_luarun.py, for differential comparison.

const REASONS := ["CREATED", "TOUCHED", "COLLIDED", "ITEM_DROPPED", "UPDATE_LOOP", "COMBINE", "COMMUNICATOR", "CHANGE_DIALOG", "END_DIALOG"]

func _clean(a: Array) -> Array:
	var out: Array = []
	for x in a:
		if x is LuaVM.LuaTable: out.append("<LuaTable>")
		elif x is LuaVM.LuaFn: out.append("<LuaFn>")
		elif x is LuaVM.Coroutine: out.append("<Coroutine>")
		elif x is Callable: out.append("<function>")
		else: out.append(x)
	return out

func _make_vm(system_bytes: PackedByteArray, reason: String, log: Array) -> LuaVM:
	var vm := LuaVM.new()
	LuaStdlib.install(vm, func(a: Array) -> void: log.append(["print"] + _clean(a)))
	var U := LuaVM.LuaTable.new()
	var names := ["GetReason","GetSource","GetVar","IsAnimPlaying","GetSelf"]
	U.meta = {"__index": func(a: Array) -> Array:
		var name: String = a[1]
		return [func(args: Array) -> Array:
			log.append([name] + _clean(args))
			match name:
				"GetReason": return [vm.G.get_v("_const").get_v(reason)]
				"GetSource": return [vm.G.get_v("_id").get_v("Inventory_PuffleBlue")]
				"GetVar": return [0]
				"IsAnimPlaying": return [false]
				"GetSelf": return [1]
			return [0]]}
	vm.G.set_v("_util", U)
	vm.call_fn(LuaVM.load_chunk(system_bytes), [])
	return vm

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root: String = args[0]
	var outp: String = args[1]
	var start := int(args[2]) if args.size() > 2 else 0
	var count := int(args[3]) if args.size() > 3 else 100000
	var names: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root + "/chunk_names.json"))
	var idx: Array = JSON.parse_string(FileAccess.get_file_as_string(root + "/arc/chunks_index.json"))
	var sys_id := ""
	for k in names: if names[k] == "system": sys_id = k
	var system := FileAccess.get_file_as_bytes("%s/arc/chunks/%s.bin" % [root, sys_id])
	var result := {}
	var i := 0
	for e in idx:
		i += 1
		if i - 1 < start or i - 1 >= start + count: continue
		var nm: String = names.get(e["id"], e["id"])
		if nm == "system": continue
		var b := FileAccess.get_file_as_bytes("%s/arc/chunks/%s.bin" % [root, e["id"]])
		var res := {}
		for r in REASONS:
			var log: Array = []
			var vm := _make_vm(system, r, log)
			vm.steps = 0
			vm.call_fn(LuaVM.load_chunk(b), [])
			var rc = vm.G.get_v("runCoroutines")
			if rc != null:
				for _k in 50: vm.call_fn(rc, [])
			var body: Array = []
			for c in log: if c[0] != "GetReason": body.append(c)
			if not body.is_empty(): res[r] = body
		result[nm] = res
	var f := FileAccess.open(outp, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("done %d chunks" % result.size())
	quit()
