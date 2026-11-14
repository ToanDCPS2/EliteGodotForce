extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for p in ["bg/Menus/Title_topscreen2", "bg/Menus/Title_bottomscreen"]:
		for ext in [".nbfc", ".nbfp", ".nbfs", ".nbcl", ".pal", ".nclr", ".nscr", ".plt", ".nbfm", ".map", ".tsb", ".gfx", ".bgx"]:
			var b = w.fs.get_by_path(p + ext)
			if b != null and b.size() > 0: print("FOUND ", p + ext, " ", b.size(), " ", b.slice(0, 24).hex_encode())
	quit()
