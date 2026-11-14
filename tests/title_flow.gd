extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	print("F title shown: ", m.title != null, " objs=", m.objs.size())
	m.title.start_pressed.emit()
	await process_frame; await process_frame
	print("F after start: title=", m.title, " objs=", m.objs.size())
	quit()
