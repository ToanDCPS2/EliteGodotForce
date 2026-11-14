extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	for t in m.model_touch:
		print(t["name"], " id=", t["id"], " mask=", m.api.interests.get(int(t["id"]), 0))
	quit()
