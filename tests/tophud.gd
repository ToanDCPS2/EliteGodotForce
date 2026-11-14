extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	for p in ["bg/MissionHUD_BG", "/bg/MissionHUD_BG", "bg/LevelSelect/Map_top"]:
		var im = EpfNbfc.load_bg(m.world, p)
		print(p, " -> ", im != null)
		if im != null: im.save_png("/tmp/p/" + p.get_file() + ".png")
	quit()
