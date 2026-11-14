extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	var t = m.model_touch[0]
	var c = t["rt"].vm.G.get_v("_const")
	for r in ["CREATED", "TOUCHED", "ITEM_DROPPED", "COLLIDED", "COMBINE", "COMMUNICATOR"]: print("K ", r, "=", c.get_v(r))
	quit()
