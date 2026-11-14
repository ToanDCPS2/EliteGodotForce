extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	for fn in ["faceFront", "bigUI", "tinyUI", "DSdigital", "Comicrazy", "smallUI", "numbers", "score"]:
		var f := EpfFont.load_font(m.world.fs, "fonts/%s.fnt" % fn)
		if f == null: continue
		var im: Image = f.render("10", Color(0.63, 0.63, 0), 0, 0)
		var ur := im.get_used_rect()
		print("FONT ", fn, " ", ur.size)
	quit()
