extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var y := 0
	var out := Image.create(330, 200, false, Image.FORMAT_RGBA8); out.fill(Color8(0, 56, 112))
	for fn in ["Comicrazy", "MackFont", "RockSnail", "SnowFort", "ComicrazyTitle", "bigUI"]:
		var f = EpfFont.load_font(m.world.fs, "fonts/%s.fnt" % fn)
		if f == null: print("no ", fn); continue
		var im: Image = f.render("You look a bit puzzled. Can I help you?", Color.WHITE)
		out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(2, y)); print(fn, " h=", im.get_height()); y += im.get_height() + 4
	out.save_png("/tmp/emu/fonts.png"); quit()
