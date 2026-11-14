extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	for ms in ["", "1.01", "3.01", "5.01", "0.05"]:
		m.set_mission(ms)
		await process_frame
		print("mission '", ms, "': objs=", m.objs.size(), " models=", m.models3d.size())
	quit()
