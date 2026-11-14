extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.set_mission("0.00")
	var i := 0
	for r in ["CoffeeShop0", "GiftShop0", "SportShop0", "Lodge0"]:
		m.load_room(r); await process_frame
		var win: Vector2 = m.get_viewport().get_visible_rect().size
		m.cam.x = m.room_size.x - (win.x / m.scale.x) * 0.5; m._center_cam = false; m._layout()
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("/tmp/emu/seam_%d.png" % i); i += 1
	quit()
