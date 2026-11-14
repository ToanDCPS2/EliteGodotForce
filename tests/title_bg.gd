extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for b in ["bg/Menus/Title_topscreen2", "bg/Menus/Title_bottomscreen"]:
		var im := EpfNbfc.load_bg(w, b)
		print(b, " ", im != null)
		if im != null: im.save_png("../previews/" + b.get_file() + ".png")
	quit()
