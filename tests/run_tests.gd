extends SceneTree
## Run: godot --headless --path . -s tests/run_tests.gd
## Loads tests/*.luc (made by tools/epf_luaasm.py), runs each on the GDScript VM and compares the resulting globals
## against tests/expected.json (produced by the Python reference VM).

func _init() -> void:
	var exp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/expected.json"))
	var fails := 0
	for name in exp.keys():
		var vm := LuaVM.new()
		LuaStdlib.install(vm)
		var bytes := FileAccess.get_file_as_bytes("res://tests/%s.luc" % name)
		var fn := LuaVM.load_chunk(bytes)
		vm.call_fn(fn, [])
		var ok := true
		for k in exp[name].keys():
			var want = exp[name][k]
			var got = vm.G.get_v(k)
			# JSON numbers come back as float
			if typeof(want) == TYPE_FLOAT: want = int(want)
			if got != want or typeof(got) != typeof(want):
				ok = false
				print("  MISMATCH %s.%s: got %s want %s" % [name, k, str(got), str(want)])
		print("%s %s" % ["PASS" if ok else "FAIL", name])
		if not ok: fails += 1
	print("tests failed: %d" % fails)
	quit(fails)
