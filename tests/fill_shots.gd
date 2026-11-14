extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	var rooms: Array = ["Stage0","Stage1"]
	for r in rooms:
		m.load_room(r)
		for i in 6: await process_frame
		if m.loop_x:
			m.cam.x = m.room_size.x - 120.0; m._layout()
			for i in 3: await process_frame
		var img := root.get_texture().get_image()
		img.save_png("../previews/fill/%s.png" % r)
		print(r, " loop=", m.loop_x, " rs=", m.room_size, " sc=", m.scale.x, " pos=", m.position, " win=", root.get_visible_rect().size)
	quit()
