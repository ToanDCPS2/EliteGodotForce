extends SceneTree
func shot(n: String) -> void:
	await create_timer(0.25).timeout
	root.get_texture().get_image().save_png("/tmp/p/pf_%s.png" % n)
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._show_menu(); await create_timer(0.2).timeout
	m.menu.show_missions()
	m.menu.show_color(); await shot("color")
	m.menu._pick_color("green"); await shot("color_green")
	m.menu.show_name()
	for c in "Rookie2":
		for k in m.menu.kb_keys:
			if k["name"] == c.to_lower() or (c == "2" and k["name"] == "two"):
				if c != c.to_lower(): m.menu.kb_shift = true
				m.menu._key(k); break
	await shot("name")
	m.menu._finish_name(); await shot("finish")
	m.menu.start_game.emit(true)
	await create_timer(1.5).timeout
	await shot("news")
	print("name=", m.player_name, " color=", m.player_color)
	quit()
