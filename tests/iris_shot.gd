extends SceneTree
## Screenshots of the room-change iris: Town -> Dock through the real door tap.
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._set_lang("en"); m.set_mission("0.00")
	m.load_room("Town0"); await create_timer(0.3).timeout
	var t = null
	for o in m.objs:
		if str(o["data"]["name"]) == "TownDoor2Dock" and o["node"].visible: t = o
	m._touch_at(t["node"].position + Vector2(32, 32))
	var shots := 0; var el := 0.0
	while el < 2.5:
		await create_timer(0.1).timeout; el += 0.1
		var img := root.get_texture().get_image(); img.save_png("/tmp/emu/iris_%02d.png" % shots); shots += 1
	print("ROOM ", m.room_prefix, " shots ", shots)
	quit()
