extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rom := NdsRom.open(a[0]); var fs := EpfArc.parse(rom.file("fs.arc"))
	for id in fs.by_id:
		var b := fs.get_entry(fs.by_id[id])
		if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() != "BMD0": continue
		var r := EpfNsbmd.parse(b)
		for m in r["models"]:
			if m["name"] != "SuperRobotTown": continue
			var t0 := Time.get_ticks_msec()
			for i in 5: EpfNsbmd.build_draws(m, m["objects"])
			print("build_draws: %d ms per pose, tris %d" % [(Time.get_ticks_msec() - t0) / 5, m["draws"].reduce(func(s, d): return s + d["verts"].size() / 3, 0)])
			quit(); return
