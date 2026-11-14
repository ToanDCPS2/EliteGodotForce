extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	for r in m.world.room_prefixes():
		if r.begins_with("Catalog") or r.begins_with("Robotomy") or r.begins_with("Jetpack") or r.begins_with("SnowCat") or r.begins_with("GarysNote"): continue
		m.load_room(r)
		for i in 4: await process_frame
		root.get_texture().get_image().save_png("../previews/all/%s_a.png" % r)
		var rs: Vector2 = m.room_size
		m.cam.x = rs.x - 100.0 if m.loop_x else 1e9
		m.cam.y = 1e9
		m._layout()
		for i in 3: await process_frame
		root.get_texture().get_image().save_png("../previews/all/%s_b.png" % r)
		print(r, " loop=", m.loop_x, " rs=", rs, " objs=", m.objs.size())
	quit()
