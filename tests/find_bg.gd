extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for p in ["bg/Menus/Title_topscreen2", "bg/Menus/Title_bottomscreen", "bg/Menus/Menus_bottom", "bg/Cutscenes/MissionIntroTop"]:
		for ext in ["", ".bgx", ".bg", ".png", ".nbfc", ".bin", ".img", ".rdt", ".tsb", ".mpb"]:
			var b = w.fs.get_by_path(p + ext)
			if b != null and b.size() > 0: print("FOUND ", p + ext, " ", b.size(), " ", b.slice(0, 16).hex_encode())
	var n := 0
	for id in w.fs.by_id:
		var b := w.fs.get_entry(w.fs.by_id[id])
		if b.size() > 8 and b.slice(0,4).get_string_from_ascii() in ["NCLR","NCGR","NSCR"]: n += 1
	print("nitro gfx entries ", n)
	print("rdt keys sample: ", w.rdt.keys.keys().filter(func(k): return str(k).to_lower().begins_with("bg/") or str(k).to_lower().contains("title")).slice(0, 40))
	quit()
