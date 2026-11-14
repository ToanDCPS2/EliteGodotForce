extends SceneTree
func shot(n: String) -> void:
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png("/tmp/p/fp_%s.png" % n)
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m._on_start_game(true); await create_timer(0.5).timeout
	var vis := []
	for o in m.objs:
		if o["node"].visible and not str(o["data"]["name"]).begins_with("TinyCoin"): vis.append(o["data"]["name"])
	print("room=", m.room_prefix, " mission=", m.mission, " obj=", m.hud.objective, " vis=", vis)
	await shot("town")
	for o in m.objs:
		if o["data"]["name"] == "AuntArctic":
			var im: Image = o["dec"]["frames"][o["frame"]]["image"]
			m._touch_at(o["node"].position + Vector2(im.get_used_rect().get_center()))
	await shot("aunt")
	print("aunt conv=", m.conv != null and m.conv.active, " text=", m.conv.items[m.conv.pos]["text"] if m.conv and m.conv.active else "")
	m.conv._close()
	m.load_room("CoffeeShop0"); await create_timer(0.4).timeout
	for o in m.objs:
		if o["data"]["name"] == "Newspaper":
			var im2: Image = o["dec"]["frames"][o["frame"]]["image"]
			m._touch_at(o["node"].position + Vector2(im2.get_used_rect().get_center()))
	await shot("paper")
	print("paper opts=", m.dialog.opt_nodes.size())
	if m.dialog.opt_nodes.size() > 0: m.dialog.opt_nodes[0].pressed.emit()
	await create_timer(1.0).timeout
	await shot("movie")
	print("cutscene=", m.cutscene != null)
	if m.cutscene != null: m.cutscene._end()
	await create_timer(1.0).timeout
	await shot("m11")
	print("room=", m.room_prefix, " mission=", m.mission, " obj=", m.hud.objective, " conv=", m.conv != null and m.conv.active)
	quit()
