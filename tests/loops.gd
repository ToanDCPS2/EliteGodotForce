extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var out := []
	for p in m.world.room_prefixes():
		if m.world.room_wraps(str(p)): out.append(str(p))
	print("WRAPS ", out)
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	for r in ["Dojo0", "CoffeeShop0", "Town0"]:
		m.load_room(r); await process_frame
		print("ROOM ", r, " loop_x=", m.loop_x)
	quit()
