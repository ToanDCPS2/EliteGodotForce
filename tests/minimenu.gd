extends SceneTree
## Walk the Mini Games menu to Cart Surfer and start it.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m._show_menu(); await create_timer(0.3).timeout
	var shots := []
	m.menu.show_minigames(); await create_timer(0.3).timeout
	shots.append(root.get_texture().get_image())
	m.menu.show_cart_surfer(); await create_timer(0.3).timeout
	shots.append(root.get_texture().get_image())
	m.menu.show_cs_difficulty(); await create_timer(0.2).timeout
	m.menu.show_cs_controls("normal"); await create_timer(0.2).timeout
	m.menu.start_minigame.emit("cartsurfer", {"mode": "normal", "controls": "pad"})
	await create_timer(4.0).timeout
	shots.append(root.get_texture().get_image())
	print("MINIGAME ", m.minigame != null, " t ", m.minigame.t if m.minigame else -1, " menu visible ", m.menu.visible)
	var w: int = shots[0].get_width() / 2; var h: int = shots[0].get_height() / 2
	var sheet := Image.create(w * 3, h, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var s: Image = shots[i]; s.resize(w, h); s.convert(Image.FORMAT_RGBA8); sheet.blit_rect(s, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(OS.get_cmdline_user_args()[0]); quit()
