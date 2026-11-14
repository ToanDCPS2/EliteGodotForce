extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.room_prefix = "SnowForts0"; m.set_mission("1.01")
	m.api.inventory[31510] = 1; m.api.inventory[31674] = 1; m.hud.set_items(m.api.inventory)
	await create_timer(0.3).timeout
	m.hud._toggle_inventory(); await create_timer(0.8).timeout
	root.get_texture().get_image().save_png("/tmp/emu/strip.png"); quit()
