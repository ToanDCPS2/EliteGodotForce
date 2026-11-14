extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	for o in m.objs:
		if str(o["name"]) == "SuperRobotTown":
			m._touch_at(o["node"].position + Vector2(20, -20)); break
	if not m.dialog.visible: m.dialog.show_lines("x", ["Test line of dialogue for the new bubble."])
	for i in 20: await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("HOME") + "/mnt/Documents/EPF-Port/dialog_shot.png")
	quit()
