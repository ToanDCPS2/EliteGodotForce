extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.player_name = "Wwat"; m.player_color = "lime"; m.api.coins = 100; m._write_save()
	m._show_menu(); await create_timer(0.2).timeout
	m.menu.show_profile(); await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("/tmp/emu/pf_port.png")
	quit()
