extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.set_mission("1.01")
	m.load_room("Town0"); await create_timer(0.3).timeout
	for o in m.objs:
		if o["data"]["name"] == "TownDoor2Coffee":
			var img: Image = o["dec"]["frames"][0]["image"]
			var c: Vector2 = o["node"].position + Vector2(img.get_used_rect().get_center())
			var wp: Vector2 = c * m.scale + m.position
			root.get_texture().get_image().save_png("/tmp/p/door_0.png")
			Input.warp_mouse(wp)
			var ev := InputEventMouseMotion.new(); ev.position = wp; Input.parse_input_event(ev)
			for k in 6:
				await create_timer(0.12).timeout
				print("state=", o["door"]["state"], " i=", o["door"]["i"])
			root.get_texture().get_image().save_png("/tmp/p/door_1.png")
			Input.warp_mouse(Vector2(5, 300))
			for k in 6:
				await create_timer(0.12).timeout
				print("state=", o["door"]["state"], " i=", o["door"]["i"])
			for n in o["door"]["st"]: print(n, " frames=", o["door"]["st"][n]["tex"].size(), " dur=", o["door"]["st"][n]["dur"])
	quit()
