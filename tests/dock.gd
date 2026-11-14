extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.set_mission("0.00"); m.load_room("Dock0"); await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("/tmp/p/dock_port.png")
	var c: Dictionary = m.world.compose_layers("Dock0")
	print("BGS ", c["bgs"].size())
	quit()
