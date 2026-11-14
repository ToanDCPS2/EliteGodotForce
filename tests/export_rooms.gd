extends SceneTree
## Exports every story room (English, mission 0.00): main-layer image + door hit rectangles, for emulator matching.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en")
	m.set_mission("0.00")
	var out := {}
	for p in m.world.room_prefixes():
		var ps := str(p)
		if ps.begins_with("Jetpack") or ps.begins_with("SnowCat") or ps.begins_with("Catalog") or ps.begins_with("LevelSelect") or ps.contains("Test"): continue
		m.load_room(ps); await process_frame
		var comp: Dictionary = m.world.compose_layers(ps)
		if comp.is_empty(): continue
		(comp["image"] as Image).save_png("/tmp/emu/rooms2/%s.png" % ps)
		var doors := []
		for o in m.objs:
			if not RomWorld.is_door(o["data"]): continue
			var img: Image = o["dec"]["frames"][o["frame"]]["image"]
			var ur := img.get_used_rect()
			var sz := Vector2(img.get_size())
			if ur.size.x <= 2 or ur.size.y <= 2: sz = Vector2(64, 64)
			var pos: Vector2 = Vector2(fposmod(float(o["bx"]), m.room_size.x), o["node"].position.y)
			doors.append({"name": o["data"]["name"], "dest": str(o["data"]["dest"]), "id": int(o["data"]["id"]), "script": str(o["data"].get("script")), "rect": [pos.x, pos.y, sz.x, sz.y], "visible": o["node"].visible})
		out[ps] = {"size": [comp["image"].get_width(), comp["image"].get_height()], "loop": m.loop_x, "doors": doors}
	var f := FileAccess.open("/tmp/emu/rooms2/rooms.json", FileAccess.WRITE); f.store_string(JSON.stringify(out, " "))
	print("EXPORTED ", out.size())
	quit()
