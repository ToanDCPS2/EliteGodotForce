extends SceneTree
func shot(n: String) -> void:
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("/tmp/p/fl_%s.png" % n)
func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._show_menu(); await shot("1_first")
	print("screen=", m.menu.screen)
	m.menu.player_name = "Wwat"; m.menu._pick_color("limegreen")
	m.menu.show_finish(); await shot("2_finish")
	m.menu.write_save(); m.menu.show_profile(); await shot("3_profile")
	m.menu.show_main(); await shot("4_main")
	m.menu.start_game.emit(not m.menu.read_save().has("mission")); await shot("5_tutorial")
	print("screen=", m.menu.screen if m.menu else "none")
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true; ev.position = Vector2(500, 300)
	m.menu._input(ev)
	await create_timer(0.6).timeout
	await shot("6_town")
	m.hud.toggle_top(); await create_timer(0.4).timeout
	await shot("7_top")
	print("room=", m.room_prefix, " mission=", m.mission, " coins=", m.api.coins, " name=", m.player_name, " unknown=", m.api.unknown_calls, " ev=", m.dbg_events)
	quit()
