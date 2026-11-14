extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	m._begin_story(); await create_timer(0.5).timeout
	m.load_room("Town0"); await create_timer(0.3).timeout
	for o in m.objs:
		if o["data"]["name"].get_file() != "CoinCountingNPC": continue
		m._touch_at(o["node"].position + o["dec"]["frames"][o["frame"]]["image"].get_size() * 0.5); await create_timer(0.2).timeout
		print("conv=", m.conv, " dlg=", m.dialog.visible)
		if m.conv == null: continue
		var step := 0
		while m.conv.active and step < 10:
			print("step ", step, " text=", m.conv.items[m.conv.pos]["text"], " opts=", m.dialog.opt_nodes.size())
			root.get_texture().get_image().save_png("/tmp/p/c2_%d.png" % step)
			if m.dialog.opt_nodes.size() > 0: m.dialog.opt_nodes[min(2, m.dialog.opt_nodes.size()-1)].pressed.emit()
			else: m.conv.click()
			await create_timer(0.2).timeout; step += 1
		print("end active=", m.conv.active, " dlg=", m.dialog.visible)
	quit()
