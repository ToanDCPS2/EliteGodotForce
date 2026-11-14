extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var fs = m.world.fs
	for p in ["flc/english/M1C1Intro03NewsPaperFull.flc", "flc/spanish/M1C1Intro03NewsPaperFull.flc", "flc/english/Intro.flc", "bg/Cutscenes/english/MissionIntroTop.nbfc", "bg/english/Menus/Menus_bottom.nbfc", "fonts/english/faceFront.fnt", "bg/LevelSelect/english/Map_top.nbfc"]:
		var d = fs.get_by_path(p)
		print("TS ", p, " -> ", (d.size() if d != null else -1))
	quit()
