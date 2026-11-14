extends SceneTree
## godot --headless --path . -s tests/verify_nsbca.gd -- rom.nds   (Python reference: 91 animations, 0 errors; SuperRobotTown_i has 42 frames)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rom := NdsRom.open(a[0]); var fs := EpfArc.parse(rom.file("fs.arc"))
	var n := 0; var bad := 0
	var town: Dictionary = {}
	for id in fs.by_id:
		var b := fs.get_entry(fs.by_id[id])
		if b.size() < 4 or b.slice(0, 4).get_string_from_ascii() != "BCA0": continue
		for an in EpfNsbca.parse(b):
			n += 1
			if an["objs"].is_empty(): bad += 1
			if an["name"].begins_with("SuperRobotTown_i") and an["frames"] == 42: town = an
	print("animations: %d (empty: %d)" % [n, bad])
	# compare frame-14 pose of Town robot idle with the Python reference matrix numbers
	for id in fs.by_id:
		var b := fs.get_entry(fs.by_id[id])
		if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() != "BMD0": continue
		var r := EpfNsbmd.parse(b)
		if r["models"].is_empty() or r["models"][0]["name"] != "SuperRobotTown": continue
		var m: Dictionary = r["models"][0]
		var t0 := Time.get_ticks_msec()
		var objs := EpfNsbca.object_matrices(town, 14, m["objects"])
		var draws := EpfNsbmd.build_draws(m, objs)
		var aabb := AABB(); var first := true
		for d in draws:
			for v in d["verts"]:
				if first: aabb = AABB(v, Vector3.ZERO); first = false
				else: aabb = aabb.expand(v)
		print("idle frame 14 bbox: %s -> %s  (%d ms)" % [aabb.position.snapped(Vector3(0.01,0.01,0.01)), (aabb.position + aabb.size).snapped(Vector3(0.01,0.01,0.01)), Time.get_ticks_msec() - t0])
		break
	quit()
