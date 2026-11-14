extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.room_prefix = "CoffeeShop0"; m.set_mission("1.01")
	await create_timer(0.5).timeout
	print("POSITIONS has 31598: ", m.api.positions.get(31598), " cam ", m.cam, " focus ", m._cam_focus)
	for o in m.objs:
		var n := str(o["data"]["name"])
		if n.contains("Puffle") or n.contains("Card") or int(o["data"]["id"]) == 31598:
			print("OBJ ", n, " id=", o["data"]["id"], " vis=", o["node"].visible, " pos=", o["node"].position, " frame=", o["frame"], " nfr=", o["dec"]["frames"].size(), " sdir=", o["data"]["sprite_dir"], " spr=", o["data"].get("sprite"))
	quit()
