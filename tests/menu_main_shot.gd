extends SceneTree
func _init():
	await process_frame
	var w := RomWorld.open(OS.get_cmdline_user_args()[0])
	var m := MainMenu.new(); root.add_child(m)
	m.setup(w, TextTable.load_id(w.fs, TextTable.GAME_STRINGS_EN))
	await process_frame
	m.snapshot().save_png("../previews/menu_main_lb.png")
	quit()
