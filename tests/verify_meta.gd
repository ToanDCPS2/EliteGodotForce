extends SceneTree
## godot --headless --path . -s tests/verify_meta.gd -- <rom.nds> <out_dir>   (compares to Python rooms.json/objects.json)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var rom := NdsRom.open(a[0]); var out: String = a[1]
	var t0 := Time.get_ticks_msec()
	var rooms := OverlayMeta.scan_rooms(rom)
	print("rooms found: %d (%d ms)" % [rooms.size(), Time.get_ticks_msec() - t0])
	var ref_r = JSON.parse_string(FileAccess.get_file_as_string(out + "/rooms.json"))
	if ref_r is Dictionary: ref_r = ref_r.values()
	var rbad := 0
	for i in mini(rooms.size(), ref_r.size()):
		var m: Dictionary = rooms[i]; var p: Dictionary = ref_r[i]
		if m["map"] != p["map"] or m["overlay"] != int(p["overlay"]) or m["width"] != int(p["width"]) or m["height"] != int(p["height"]) or m["tileset"] != p["tileset"] or int(m["parallax"][0]) != int(p["parallax"][0]):
			rbad += 1
			if rbad < 4: print("  room diff: ", m, p)
	print("rooms: mine %d, python %d, mismatches %d" % [rooms.size(), ref_r.size(), rbad])
	t0 = Time.get_ticks_msec()
	var objs := OverlayMeta.scan_objects(rom)
	var total := 0
	for k in objs: total += objs[k].size()
	print("objects: %d instances in %d overlays (%d ms)" % [total, objs.size(), Time.get_ticks_msec() - t0])
	var ref_o: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out + "/objects.json"))
	var obad := 0; var ptotal := 0
	for k in ref_o.keys():
		ptotal += ref_o[k].size()
		if not objs.has(k) or objs[k].size() != ref_o[k].size(): obad += 1; continue
		for i in ref_o[k].size():
			var m: Dictionary = objs[k][i]; var p: Dictionary = ref_o[k][i]
			if m["name"] != p["name"] or m["x"] != int(p["x"]) or m["y"] != int(p["y"]) or m["event"] != int(p["event"]) or m["w8"] != int(p["w8"]) or m["id"] != int(p["id"]) or m["sprite_dir"] != p["sprite_dir"] or m["script"] != p["script"]:
				obad += 1
				if obad < 4: print("  obj diff: ", m, p)
				break
	print("objects: python %d, overlays with differences: %d" % [ptotal, obad])
	quit()
