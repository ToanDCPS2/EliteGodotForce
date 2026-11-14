extends SceneTree
## The same screens in each language: title, main menu, Cart Surfer title, help page 1. Sheet: one row per language.
func _init() -> void:
	root.size = Vector2i(1152, 648)
	var m = load("res://epf/game/main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.8).timeout
	m.music.muted = true
	var rows := []
	for l in ["en", "fr", "es"]:
		m._set_lang(l)
		var shots := []
		if m.title != null: m.title.queue_free(); m.title = null
		m._show_title(); await create_timer(0.6).timeout
		shots.append(root.get_texture().get_image())
		if m.title != null: m.title.queue_free(); m.title = null
		m._show_menu(); await create_timer(0.4).timeout
		shots.append(root.get_texture().get_image())
		m.menu.show_cart_surfer(); await create_timer(0.3).timeout
		shots.append(root.get_texture().get_image())
		m.menu.show_cs_help(0); await create_timer(0.3).timeout
		shots.append(root.get_texture().get_image())
		rows.append(shots)
	var sheet := Image.create(384 * 4, 216 * 3, false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in rows[r].size():
			var im: Image = rows[r][c]; im.convert(Image.FORMAT_RGBA8); im.resize(384, 216, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(im, Rect2i(0, 0, 384, 216), Vector2i(c * 384, r * 216))
	sheet.save_png(OS.get_cmdline_user_args()[0]); quit()
