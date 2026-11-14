extends SceneTree
func _init() -> void:
	var m = load("res://epf/game/main.tscn").instantiate()
	root.add_child(m)
	await process_frame; await process_frame
	m.title.start_pressed.emit(); await process_frame; await process_frame
	m.menu.show_missions(); m.menu.btns[0].cb.call(); await process_frame; await process_frame
	print("F models=", m.models3d.size())
	m.model_hires = true; m.apply_model_tuning(); await process_frame
	for e in m.models3d: print("F ", e["name"], " vp=", e["vp"].size, " scale=", e["spr"].scale)
	m.model_hires = false; m.apply_model_tuning()
	for e in m.models3d: print("F off vp=", e["vp"].size, " scale=", e["spr"].scale)
	quit()
