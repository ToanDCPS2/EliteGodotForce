extends SceneTree
func shot(n: String) -> void:
	await create_timer(0.15).timeout
	root.get_texture().get_image().save_png("/tmp/p/hud_%s.png" % n)
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	print("sfx count=", m.sfx.count(), " s38=", m.sfx.stream(38) != null)
	if m.title != null: m.title.queue_free(); m.title = null
	m.api.vars.clear()
	m._begin_story(); await create_timer(0.4).timeout
	while m.dialog.visible: m.dialog.advance(); await create_timer(0.05).timeout
	await shot("town")
	m.load_room("CoffeeShop0"); await create_timer(0.4).timeout
	await shot("coffee_obj")
	var g := 0
	while m.dialog.visible and g < 6:
		if m.conv != null and m.conv.active: m.conv.click()
		else: m.dialog.advance()
		await create_timer(0.1).timeout; g += 1
	for o in m.objs:
		if o["data"]["name"] == "BluePuffleBouncy":
			m._touch_at(o["node"].position + o["dec"]["frames"][o["frame"]]["image"].get_size() * 0.5)
	await shot("popup")
	print("inv=", m.api.inventory, " hud items=", m.hud.items, " puffle=", m.hud.puffle_item)
	m.dialog.advance()
	m.hud._toggle_inventory()
	await shot("inventory")
	m._on_items_combined(31510, 31510)
	await shot("combine_same")
	m.dialog.visible = false
	m._on_item_dropped(31510, Vector2(600, 300))
	await shot("drop")
	print("unknown=", m.api.unknown_calls)
	quit()
