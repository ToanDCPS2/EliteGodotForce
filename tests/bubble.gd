extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	print("bubbles:", m.dialog.bubbles.keys(), " model_touch:", m.model_touch.size())
	for t in m.model_touch:
		m._touch_at(t["rect"].get_center())
		print(t["name"], " visible:", m.dialog.visible, " kind:", m.dialog.kind, " anchor:", m.dialog.anchor, " text:", m.dialog.label.text.left(50))
		m.dialog.visible = false
	quit()
