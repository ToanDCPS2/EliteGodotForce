extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	m._begin_story(); await create_timer(0.5).timeout
	for r in ["Town0","CoffeeShop0","Dock0"]:
		m.load_room(r); await create_timer(0.3).timeout
		print(r," objs=",m.objs.size())
		for o in m.objs:
			if not o["node"].visible: continue
			var n: String = o["data"]["name"].get_file()
			if n.begins_with("TinyCoin"): continue
			var c = o["node"].position + Vector2(6,6)
			m._touch_at(c)
			await create_timer(0.1).timeout
			if m.conv != null and m.conv.active:
				print("CONV ", r, " ", n, " items=", m.conv.items.size(), " opts=", m.dialog.opt_nodes.size())
				var img := root.get_texture().get_image()
				img.save_png("/tmp/p/conv_%s_%s.png" % [r, n])
				# click through
				var guard := 0
				while m.conv.active and guard < 12:
					if m.dialog.opt_nodes.size() > 0: m.dialog.opt_nodes[0].pressed.emit()
					else: m.conv.click()
					await create_timer(0.1).timeout; guard += 1
				print("  done active=", m.conv.active)
	quit()
