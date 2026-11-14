extends SceneTree
## Shots of every Cart Surfer menu screen at 1152x648.
func _init() -> void:
	root.size = Vector2i(1152, 648)
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m._show_menu(); await create_timer(0.3).timeout
	var shots := []
	for step in ["minigames", "title", "difficulty", "controls", "help0", "help2", "results"]:
		match step:
			"minigames": m.menu.show_minigames()
			"title": m.menu.show_cart_surfer()
			"difficulty": m.menu.show_cs_difficulty()
			"controls": m.menu.show_cs_controls("normal")
			"help0": m.menu.show_cs_help(0)
			"help2": m.menu.show_cs_help(2)
			"results": m.menu.show_cs_results(80, 8, 108, true, true)
		await create_timer(0.4).timeout
		var im: Image = root.get_texture().get_image(); im.resize(576, 324); shots.append(im)
	var sheet := Image.create(576 * 4, 324 * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Image = shots[i]; s.convert(Image.FORMAT_RGBA8); sheet.blit_rect(s, Rect2i(0, 0, 576, 324), Vector2i((i % 4) * 576, (i / 4) * 324))
	sheet.save_png(OS.get_cmdline_user_args()[0]); quit()
