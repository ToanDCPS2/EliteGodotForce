extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.music.muted = true
	if m.title != null: m.title.queue_free(); m.title = null
	m.api.vars.clear()
	m._begin_story(); await create_timer(0.6).timeout
	while m.dialog.visible: m.dialog.advance(); await create_timer(0.05).timeout
	await create_timer(0.3).timeout
	print("room=", m.room_prefix, " dlg=", m.dialog.visible, " vars=", m.api.vars)
	root.get_texture().get_image().save_png("/tmp/p/town0.png")
	m.load_room("CoffeeShop0"); await create_timer(0.5).timeout
	print("coffee dlg=", m.dialog.visible, " conv=", m.conv != null and m.conv.active, " vars=", m.api.vars)
	root.get_texture().get_image().save_png("/tmp/p/coffee0.png")
	quit()
