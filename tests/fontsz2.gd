extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m._set_lang("en")
	var lbl: String = m.game_text.get_text(158).strip_edges() + " 0"
	for fn in ["faceFront", "bigUI", "tinyUI", "DSdigital", "Comicrazy"]:
		var f := EpfFont.load_font(m.world.fs, "fonts/%s.fnt" % fn)
		if f == null: continue
		var im: Image = f.render(lbl, Color.WHITE, 0, 0)
		var ur := im.get_used_rect()
		var n := 0
		for y in im.get_height():
			for x in im.get_width():
				var c := im.get_pixel(x, y)
				if c.a > 0.5 and c.r > 0.78: n += 1
		print("FONT ", fn, " ", ur.size, " white px ", n)
	quit()
