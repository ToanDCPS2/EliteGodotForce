extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	var hits := 0
	for o in m.objs:
		if o["rt"] == null: continue
		m._touch_at(o["node"].position + Vector2(o["dec"]["frames"][0]["image"].get_size()) * 0.5 if false else o["node"].position)
		if m.dialog.visible:
			hits += 1
			if hits <= 4: print(o["data"]["name"], " -> ", m.dialog.label.text)
			m.dialog.visible = false
	print("objects:", m.objs.size(), " scripted dialogues opened:", hits)
	quit()
