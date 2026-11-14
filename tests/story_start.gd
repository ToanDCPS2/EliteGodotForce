extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.api.vars.clear()
	m._begin_story(); await create_timer(0.6).timeout
	print("room=", m.room_prefix, " vars=", m.api.vars)
	root.get_texture().get_image().save_png("/tmp/p/start0.png")
	while m.dialog.visible: m.dialog.advance(); await create_timer(0.05).timeout
	await create_timer(0.3).timeout
	var k := 0
	while k < 8:
		if m.conv != null and m.conv.active:
			print("auto ", k, " kind=", m.conv.items[m.conv.pos]["kind"], " '", m.conv.items[m.conv.pos]["text"], "'")
			root.get_texture().get_image().save_png("/tmp/p/auto_%d.png" % k)
			m.conv.click(); await create_timer(0.1).timeout
		k += 1
	var vis := []
	for o in m.objs:
		if o["node"].visible and not o["data"]["name"].begins_with("TinyCoin"): vis.append(o["data"]["name"])
	print("visible=", vis)
	root.get_texture().get_image().save_png("/tmp/p/start1.png")
	for o in m.objs:
		if o["data"]["name"] != "BluePuffleBouncy": continue
		var step := 0
		while step < 6:
			m._touch_at(o["node"].position + o["dec"]["frames"][o["frame"]]["image"].get_size() * 0.5); await create_timer(0.15).timeout
			root.get_texture().get_image().save_png("/tmp/p/puf_%d.png" % step)
			var t := ""
			if m.conv != null and m.conv.active: t = m.conv.items[m.conv.pos]["text"]
			print("touch ", step, " '", t, "' dlg=", m.dialog.visible, " shown=", o["node"].visible)
			while m.dialog.visible:
				if m.conv != null and m.conv.active: m.conv.click()
				else: m.dialog.advance()
				await create_timer(0.05).timeout
			step += 1
			if not o["node"].visible: break
	print("vars=", m.api.vars, " inv=", m.api.inventory)
	quit()
