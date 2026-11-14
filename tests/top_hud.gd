extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.player_color = "green"; m.api.coins = 100
	m._show_menu(); await create_timer(0.2).timeout
	m.menu.player_color = "green"; m.hud.player_doll = m.menu.doll_image(); m.menu.queue_free(); m.menu = null
	m._new_story()
	await create_timer(1.0).timeout
	m.hud.toggle_top(); await create_timer(0.8).timeout
	var im: Image = m.hud._top_image(); im.save_png("/tmp/emu/top_port.png")
	root.get_texture().get_image().save_png("/tmp/emu/top_full.png")
	quit()
