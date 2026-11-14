extends SceneTree
func _init() -> void:
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	for p in ["bg/Menus/Title_topscreen", "bg/Menus/Title_topscreen1", "bg/Menus/Title_topscreen3", "bg/Menus/Title_topscreen_en", "bg/Menus/Title_topscreen_english", "bg/Menus/Title_topscreen2", "bg/Menus/Title_top", "bg/Menus/Title_topscreen_fr", "bg/Menus/spanish/Title_topscreen2", "bg/Menus/french/Title_topscreen2", "bg/Menus/Title_bottomscreen"]:
		var b = w.fs.get_by_path(p + ".nbfc"); print(p, " ", -1 if b == null else b.size())
	quit()
