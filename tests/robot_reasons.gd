extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	var t = m.model_touch[0]
	for r in ["CREATED", "TOUCHED", "ITEM_DROPPED", "COLLIDED", "COMBINE"]:
		var b: int = m.api.events.size()
		t["rt"].fire(m.api, r, 1000001 if r == "ITEM_DROPPED" else 0)
		var ev := []
		for e in m.api.events.slice(b): ev.append([e["fn"], e["args"]])
		print(r, " -> ", ev)
	quit()
