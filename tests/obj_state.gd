extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	var hidden := 0
	for o in m.objs: if not o["node"].visible: hidden += 1
	print("hidden after CREATED: ", hidden, " of ", m.objs.size())
	var clicked := 0; var gone := 0
	for o in m.objs.duplicate():
		if o["rt"] == null or not o["node"].visible: continue
		m._touch_at(o["node"].position + Vector2(2, 2))
		if m.dialog.visible: m.dialog.visible = false
		clicked += 1
		if not o["node"].visible: gone += 1
	print("touched ", clicked, " objects; ", gone, " vanished (pick-ups)")
	quit()
