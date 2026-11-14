extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	for n in ["bg/Menus/Menus_bottom", "bg/Menus/Menus_top"]:
		var im: Image = EpfNbfc.load_bg(m.world, n)
		if im: im.save_png("/tmp/emu/" + n.get_file() + ".png"); print("BG ", n, " ", im.get_size())
	quit()
