extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var im: Image = EpfNbfc.load_bg(m.world, "bg/MissionHUD_BG")
	im.save_png("/tmp/emu/MissionHUD_BG.png"); print("BG ", im.get_size(), " ", im.get_format())
	quit()
