extends SceneTree
func shot(n: String) -> void:
	await create_timer(0.25).timeout
	root.get_texture().get_image().save_png("/tmp/p/h2_%s.png" % n)
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.api.vars.clear()
	m._begin_story(); await create_timer(0.4).timeout
	while m.dialog.visible: m.dialog.advance(); await create_timer(0.05).timeout
	await shot("town")
	m.load_room("CoffeeShop0"); await create_timer(0.4).timeout
	var g := 0
	await create_timer(0.5).timeout
	while m.dialog.visible and g < 12:
		if m.conv != null and m.conv.active: m.conv.click()
		else: m.dialog.advance()
		await create_timer(0.1).timeout; g += 1
	for o in m.objs:
		if o["data"]["name"] == "BluePuffleBouncy":
			var im: Image = o["dec"]["frames"][o["frame"]]["image"]
			m._touch_at(o["node"].position + Vector2(im.get_used_rect().get_center()))
	await create_timer(0.1).timeout
	print("inv=", m.api.inventory, " tr=", Rect2(m.dialog._tr.position, m.dialog._tr.size), " lab=", Rect2(m.dialog.label.position, m.dialog.label.size), " item=", m.dialog.item_rect.position if m.dialog.item_rect else null)
	await shot("popup")
	m.dialog.advance()
	m.hud._toggle_inventory()
	await create_timer(0.08).timeout
	root.get_texture().get_image().save_png("/tmp/p/h2_invmid.png")
	await shot("inventory")
	m.hud.toggle_top()
	await shot("top")
	quit()
